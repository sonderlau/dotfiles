/**
 * 计划审阅层。
 *
 * 全屏模式下 ↑↓ / 滚轮默认滚的是聊天记录（`tui.altScreen.lineUp`），编辑区里的
 * 组件抢不到。所以这里用盖住屏幕的 overlay，自己选行、自己滚动。标题只改颜色和
 * 加粗，不改字号。意见按原文行号写成 `L150: ...` 交回模型。
 * 底部操作是可点击按钮；悬停时填色、加下划线，并把左空格换成 `>`。键盘快捷键仍可用。
 * `approve` 要在 1.2 秒内操作两次才会通过。键盘 `a` 和鼠标点击是同一种操作，可以混着来。
 */

import type { Theme } from "@earendil-works/pi-coding-agent";
import {
	Editor,
	type EditorTheme,
	Key,
	matchesKey,
	type TUI,
	type TuiMouseEvent,
	type TuiMouseEventResult,
	visibleWidth,
	wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { formatLineComment, headingText, parsePlanLines, type PlanSourceLine } from "./review-lines.ts";

export type PlanReviewResult =
	| { kind: "execute" | "doc-only"; notes: string[] }
	| { kind: "revise"; comments: string[] }
	| { kind: "reject" };

type ReviewActionId = "comment" | "send" | "approve" | "doc" | "reject" | "save" | "cancel";

interface ReviewAction {
	id: ReviewActionId;
	key: string;
	label: string;
	enabled: boolean;
	tone: Slot;
	pending?: boolean;
}

interface ButtonHit {
	id: ReviewActionId;
	y: number;
	x: number;
	width: number;
	enabled: boolean;
}

type ReviewUI = {
	custom: <T>(
		factory: (
			tui: TUI,
			theme: Theme,
			keybindings: unknown,
			done: (result: T) => void,
		) => {
			render: (width: number) => string[];
			invalidate: () => void;
			handleInput: (data: string) => void;
			handleMouse?: (event: TuiMouseEvent) => TuiMouseEventResult | undefined;
		},
		options?: { overlay?: boolean; overlayOptions?: Record<string, unknown> },
	) => Promise<T>;
};

interface VisualRow {
	source: number;
	text: string;
}

export async function showPlanReview(ui: ReviewUI, plan: string): Promise<PlanReviewResult | undefined> {
	const sources = parsePlanLines(plan);
	return ui.custom<PlanReviewResult | undefined>(
		(tui, theme, _kb, done) => {
			const editorTheme: EditorTheme = {
				borderColor: (s) => theme.fg("accent", s),
				selectList: {
					selectedPrefix: (t) => theme.fg("accent", t),
					selectedText: (t) => theme.fg("accent", t),
					description: (t) => theme.fg("muted", t),
					scrollInfo: (t) => theme.fg("dim", t),
					noMatch: (t) => theme.fg("warning", t),
				},
			};
			const editor = new Editor(tui, editorTheme);
			const comments = new Map<number, string[]>();
			let commenting = false;
			let focused = false;
			let selected = 0;
			let scroll = 0;
			let cached: string[] | undefined;
			let cachedWidth = 0;
			let rows: VisualRow[] = [];
			let hoverId: ReviewActionId | undefined;
			let viewWidth = 80;
			let bodyRows = 4;
			let buttonHits: ButtonHit[] = [];
			let approveUntil = 0;
			let approveTimer: ReturnType<typeof setTimeout> | undefined;

			function syncEditorFocus(): void {
				editor.focused = focused && commenting;
			}
			function refresh(): void {
				cached = undefined;
				tui.requestRender();
			}
			function notes(): string[] {
				const lines: string[] = [];
				for (const number of [...comments.keys()].sort((a, b) => a - b)) {
					for (const text of comments.get(number) ?? []) lines.push(formatLineComment(number, text));
				}
				return lines;
			}
			editor.onSubmit = (value) => {
				const text = value.trim();
				const line = sources[selected];
				if (text && line) {
					const list = comments.get(line.number) ?? [];
					list.push(text);
					comments.set(line.number, list);
				}
				editor.setText("");
				commenting = false;
				syncEditorFocus();
				refresh();
			};

			function move(delta: number): void {
				if (sources.length === 0) return;
				selected = Math.max(0, Math.min(sources.length - 1, selected + delta));
				reveal();
				refresh();
			}
			function reveal(): void {
				const index = rows.findIndex((row) => row.source === selected);
				if (index < 0) return;
				const view = bodyHeight();
				if (index < scroll) scroll = index;
				else if (index >= scroll + view) scroll = index - view + 1;
			}
			function approveArmed(): boolean {
				return Date.now() < approveUntil;
			}
			function clearApproveArm(): void {
				approveUntil = 0;
				if (!approveTimer) return;
				clearTimeout(approveTimer);
				approveTimer = undefined;
			}
			function armApprove(): void {
				clearApproveArm();
				approveUntil = Date.now() + APPROVE_CONFIRM_MS;
				approveTimer = setTimeout(() => {
					approveTimer = undefined;
					approveUntil = 0;
					refresh();
				}, APPROVE_CONFIRM_MS);
				refresh();
			}
			function requestApprove(): void {
				if (!approveArmed()) {
					armApprove();
					return;
				}
				activate("approve");
			}
			function currentActions(): ReviewAction[] {
				return reviewActions(commenting, notes().length > 0, approveArmed());
			}
			function prefixText(): string {
				return commenting ? `L${sources[selected]?.number ?? "?"}  ` : " ";
			}
			function bodyHeight(): number {
				const term = process.stdout.rows || Number(process.env.LINES) || 24;
				const buttons = planActionRows(currentActions(), Math.max(8, viewWidth), visibleWidth(prefixText())).length;
				const editorReserve = commenting ? 3 : 0;
				return Math.max(4, term - 3 - buttons - editorReserve);
			}
			function activate(id: ReviewActionId): void {
				const action = currentActions().find((item) => item.id === id);
				if (!action?.enabled) return;
				clearApproveArm();
				hoverId = undefined;
				switch (id) {
					case "reject":
						done({ kind: "reject" });
						return;
					case "approve":
						done({ kind: "execute", notes: notes() });
						return;
					case "doc":
						done({ kind: "doc-only", notes: notes() });
						return;
					case "send":
						done({ kind: "revise", comments: notes() });
						return;
					case "comment":
						commenting = true;
						syncEditorFocus();
						refresh();
						return;
					case "save":
						editor.onSubmit?.(editor.getText());
						return;
					case "cancel":
						editor.setText("");
						commenting = false;
						syncEditorFocus();
						refresh();
						return;
				}
			}

			function handleInput(data: string): void {
				if (commenting) {
					if (matchesKey(data, Key.escape)) return activate("cancel");
					editor.handleInput(data);
					refresh();
					return;
				}
				if (matchesKey(data, Key.escape)) return activate("reject");
				if (matchesKey(data, "a")) return requestApprove();
				if (approveArmed()) {
					clearApproveArm();
					refresh();
				}
				if (matchesKey(data, "d")) return activate("doc");
				if (matchesKey(data, "s")) return activate("send");
				if (matchesKey(data, "c") || matchesKey(data, Key.enter)) return activate("comment");
				if (matchesKey(data, Key.up) || matchesKey(data, "k")) return move(-1);
				if (matchesKey(data, Key.down) || matchesKey(data, "j")) return move(1);
				if (matchesKey(data, Key.pageUp)) return scrollBy(-bodyHeight());
				if (matchesKey(data, Key.pageDown)) return scrollBy(bodyHeight());
				if (matchesKey(data, Key.home)) {
					selected = 0;
					scroll = 0;
					refresh();
					return;
				}
				if (matchesKey(data, Key.end)) {
					selected = Math.max(0, sources.length - 1);
					reveal();
					refresh();
				}
			}

			function scrollBy(delta: number): void {
				const max = Math.max(0, rows.length - bodyHeight());
				scroll = Math.max(0, Math.min(max, scroll + delta));
				const visible = rows.slice(scroll, scroll + bodyHeight());
				if (visible.length > 0 && !visible.some((row) => row.source === selected)) {
					selected = delta < 0 ? visible[0]!.source : visible[visible.length - 1]!.source;
				}
				refresh();
			}

			function hitAt(x: number, y: number): ButtonHit | undefined {
				return buttonHits.find((hit) => hit.y === y && x >= hit.x && x < hit.x + hit.width);
			}
			function handleMouse(event: TuiMouseEvent): TuiMouseEventResult | undefined {
				if (event.type === "wheel") {
					scrollBy(event.wheelDelta && event.wheelDelta < 0 ? -3 : 3);
					return { handled: true };
				}
				if (event.type === "move") {
					const next = hitAt(event.x, event.y)?.id;
					if (next === hoverId) return { handled: true, render: false };
					hoverId = next;
					cached = undefined;
					return { handled: true, render: true };
				}
				if (event.type === "press" && event.button === "left") {
					return { handled: true, focus: true, render: false };
				}
				if (event.type === "click" && event.button === "left") {
					const hit = hitAt(event.x, event.y);
					if (hit?.id === "approve") {
						requestApprove();
						return { handled: true, focus: true, render: true };
					}
					if (hit) {
						activate(hit.id);
						return { handled: true, focus: true, render: true };
					}
					if (approveArmed()) {
						clearApproveArm();
						refresh();
					}
					const bodyTop = 2;
					const visibleCount = Math.min(bodyRows, Math.max(0, rows.length - scroll));
					const visibleIndex = event.y - bodyTop;
					if (visibleIndex >= 0 && visibleIndex < visibleCount) {
						const row = rows[scroll + visibleIndex];
						if (row) {
							selected = row.source;
							refresh();
						}
					}
					return { handled: true, focus: true };
				}
				return { handled: true };
			}

			function render(width: number): string[] {
				viewWidth = width;
				if (cached && cachedWidth === width && rows.length > 0) return cached;
				cachedWidth = width;
				const inner = Math.max(8, width - 2);
				rows = layout(sources, comments, theme, inner);
				bodyRows = bodyHeight();
				const maxScroll = Math.max(0, rows.length - bodyRows);
				scroll = Math.max(0, Math.min(scroll, maxScroll));
				reveal();
				const slice = rows.slice(scroll, scroll + bodyRows);
				const lines: string[] = [];
				const rule = theme.fg("borderMuted", "─".repeat(Math.max(1, width)));
				const line = sources[selected];
				const title = `${theme.bold(theme.fg("warning", "Plan"))}  ${theme.fg("dim", line ? `L${line.number}` : "")}  ${theme.fg("dim", `${selected + 1}/${Math.max(1, sources.length)}`)}`;
				lines.push(rule);
				lines.push(pad(` ${title}`, width));
				for (const row of slice) {
					const painted = pad(row.text, width);
					lines.push(row.source === selected ? theme.bg("selectedBg", painted) : painted);
				}
				while (lines.length < bodyRows + 2) lines.push(pad("", width));
				const bar = paintActionBar(currentActions(), theme, hoverId, width, lines.length, prefixText());
				buttonHits = bar.hits;
				for (const barLine of bar.lines) lines.push(pad(barLine, width));
				if (commenting) {
					for (const editorLine of editor.render(inner)) lines.push(pad(` ${editorLine}`, width));
				}
				lines.push(rule);
				cached = lines;
				return lines;
			}

			return {
				render,
				invalidate: () => {
					cached = undefined;
					editor.invalidate();
				},
				handleInput,
				handleMouse,
				get focused() {
					return focused;
				},
				set focused(value: boolean) {
					focused = value;
					syncEditorFocus();
					cached = undefined;
				},
			};
		},
		{
			overlay: true,
			overlayOptions: {
				anchor: "top-left",
				row: 0,
				col: 0,
				width: "100%",
				maxHeight: "100%",
				margin: 0,
			},
		},
	);
}

function layout(sources: PlanSourceLine[], comments: Map<number, string[]>, theme: Theme, width: number): VisualRow[] {
	const gutter = 8;
	const textWidth = Math.max(1, width - gutter);
	const rows: VisualRow[] = [];
	for (let index = 0; index < sources.length; index++) {
		const source = sources[index]!;
		const mark = comments.has(source.number) ? theme.fg("warning", "✎") : " ";
		const number = theme.fg("dim", String(source.number).padStart(4, " "));
		const body = styleLine(source, theme);
		const wrapped = wrapTextWithAnsi(body, textWidth);
		const first = wrapped[0] ?? "";
		rows.push({ source: index, text: `${number} ${mark} ${first}` });
		for (const extra of wrapped.slice(1)) rows.push({ source: index, text: `${" ".repeat(gutter)}${extra}` });
		for (const comment of comments.get(source.number) ?? []) {
			const preview = wrapTextWithAnsi(theme.fg("warning", formatLineComment(source.number, comment)), textWidth);
			for (const line of preview.slice(0, 2)) rows.push({ source: index, text: `${" ".repeat(gutter)}${line}` });
		}
	}
	return rows;
}

/**
 * 计划 markdown 的上色。只用当前 theme 的语义槽，不写死色值。
 *
 * 标题按层级用不同职责的色，避免都落在 `text` / `mdHeading` 上
 *（grok-build 里这两个槽是同一个白）：
 *   h1 warning        要拍板的标题，注意色
 *   h2 mdLink         章节，链接/导航色
 *   h3 syntaxType     分类，类型色
 *   h4 success        具体改动，成功/增加色
 *   h5 syntaxString   细节，字面量色
 *   h6 syntaxComment  次要标题，注释色
 *
 * 其余按槽的本职：列表点 `mdListBullet`，序号 `syntaxNumber`，
 * 引用 `mdQuote`，分割线 `mdHr`，代码块 `mdCodeBlock` / `mdCodeBlockBorder`，
 * 行内代码用 `syntaxString`（字面量；`mdCode` 在当前皮肤里和正文同色），
 * 链接文字 `mdLink`、地址 `mdLinkUrl`，强调 `accent`，斜体 `thinkingText`。
 * 任务：已勾 `success`，未勾 `warning`。
 */
type Slot = Parameters<Theme["fg"]>[0];

const HEADING_SLOT: Record<1 | 2 | 3 | 4 | 5 | 6, Slot> = {
	1: "warning",
	2: "mdLink",
	3: "syntaxType",
	4: "success",
	5: "syntaxString",
	6: "syntaxComment",
};

const TASK = /^(\s*)([-*+])(\s+)(\[[ xX]\])(\s*)(.*)$/;
const BULLET = /^(\s*)([-*+])(\s+)(.*)$/;
const ORDERED = /^(\s*)(\d+[.)])(\s+)(.*)$/;
const QUOTE = /^(\s*)(>+)(\s?)(.*)$/;
const HR = /^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/;
const TABLE_RULE = /^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/;
const FENCE = /^(\s*)(`{3,})(.*)$/;

function styleLine(source: PlanSourceLine, theme: Theme): string {
	const fence = FENCE.exec(source.text);
	if (fence) {
		const [, indent, ticks, rest] = fence;
		return theme.fg("dim", indent!) + theme.fg("mdCodeBlockBorder", ticks!) + (rest ? theme.fg("syntaxKeyword", rest) : "");
	}
	if (source.fence) return theme.fg("mdCodeBlock", source.text);
	if (source.heading > 0) {
		const slot = HEADING_SLOT[source.heading as 1 | 2 | 3 | 4 | 5 | 6] ?? "mdHeading";
		const label = headingText(source.text) || source.text;
		return theme.bold(theme.fg(slot, label));
	}
	if (HR.test(source.text) || TABLE_RULE.test(source.text)) return theme.fg("mdHr", source.text);

	const task = TASK.exec(source.text);
	if (task) {
		const [, indent, marker, gap, box, after, rest] = task;
		const done = box!.toLowerCase().includes("x");
		const markSlot: Slot = done ? "success" : "warning";
		return (
			theme.fg("dim", indent!) +
			theme.fg("mdListBullet", marker!) +
			gap! +
			theme.fg(markSlot, box!) +
			after! +
			styleInline(rest!, theme, done ? "muted" : "text")
		);
	}
	const bullet = BULLET.exec(source.text);
	if (bullet) {
		const [, indent, marker, gap, rest] = bullet;
		return theme.fg("dim", indent!) + theme.fg("mdListBullet", marker!) + gap! + styleInline(rest!, theme);
	}
	const ordered = ORDERED.exec(source.text);
	if (ordered) {
		const [, indent, marker, gap, rest] = ordered;
		return theme.fg("dim", indent!) + theme.fg("syntaxNumber", marker!) + gap! + styleInline(rest!, theme);
	}
	const quote = QUOTE.exec(source.text);
	if (quote) {
		const [, indent, marks, gap, rest] = quote;
		return theme.fg("dim", indent!) + theme.fg("syntaxComment", marks!) + gap! + styleInline(rest!, theme, "mdQuote");
	}
	if (source.text.includes("|") && source.text.split("|").length >= 3) return styleTable(source.text, theme);
	return styleInline(source.text, theme);
}

const INLINE =
	/(\*\*[^*\n]+?\*\*|~~[^~\n]+?~~|(?<!\*)\*[^*\n]+?\*(?!\*)|`[^`\n]+`|\[[^\]\n]+\]\([^)\n]+\)|https?:\/\/[^\s)]+)/g;

function styleInline(text: string, theme: Theme, body: Slot = "text"): string {
	const parts = text.split(INLINE);
	return parts
		.map((part) => {
			if (part.startsWith("**") && part.endsWith("**") && part.length >= 4) {
				return theme.bold(theme.fg("accent", part.slice(2, -2)));
			}
			if (part.startsWith("~~") && part.endsWith("~~") && part.length >= 4) {
				return theme.strikethrough(theme.fg("dim", part.slice(2, -2)));
			}
			if (part.startsWith("*") && part.endsWith("*") && part.length >= 3) {
				return theme.italic(theme.fg("thinkingText", part.slice(1, -1)));
			}
			if (part.startsWith("`") && part.endsWith("`") && part.length >= 3) {
				return theme.fg("syntaxString", part.slice(1, -1));
			}
			const link = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(part);
			if (link) {
				return (
					theme.fg("syntaxPunctuation", "[") +
					theme.fg("mdLink", link[1]!) +
					theme.fg("syntaxPunctuation", "](") +
					theme.fg("mdLinkUrl", link[2]!) +
					theme.fg("syntaxPunctuation", ")")
				);
			}
			if (part.startsWith("http://") || part.startsWith("https://")) return theme.underline(theme.fg("mdLink", part));
			return part ? theme.fg(body, part) : part;
		})
		.join("");
}

function styleTable(text: string, theme: Theme): string {
	const cells = text.split("|");
	return cells
		.map((cell, index) => {
			const painted = styleInline(cell, theme);
			return index === cells.length - 1 ? painted : painted + theme.fg("syntaxPunctuation", "|");
		})
		.join("");
}

function pad(text: string, width: number): string {
	const gap = Math.max(0, width - visibleWidth(text));
	return text + " ".repeat(gap);
}

/** 按钮文字。悬停把左侧空格换成 `>`，宽度不变，点击区域不会跳。 */
export function buttonFace(key: string, label: string, hovered: boolean): string {
	return `[${hovered ? ">" : " "}${key} ${label} ]`;
}

const APPROVE_CONFIRM_MS = 1200;

export function reviewActions(commenting: boolean, canSend: boolean, approvePending = false): ReviewAction[] {
	if (commenting) {
		return [
			{ id: "save", key: "enter", label: "save", enabled: true, tone: "success" },
			{ id: "cancel", key: "esc", label: "cancel", enabled: true, tone: "warning" },
		];
	}
	return [
		{ id: "comment", key: "c", label: "comment", enabled: true, tone: "text" },
		{ id: "send", key: "s", label: "send", enabled: canSend, tone: "accent" },
		{
			id: "approve",
			key: "a",
			label: approvePending ? "confirm" : "approve",
			enabled: true,
			tone: approvePending ? "warning" : "success",
			pending: approvePending,
		},
		{ id: "doc", key: "d", label: "doc only", enabled: true, tone: "text" },
		{ id: "reject", key: "esc", label: "reject", enabled: true, tone: "error" },
	];
}

/** 按可见宽度折行。`x` 是按钮左缘，和渲染时的单元格一致。 */
export function planActionRows(
	actions: Pick<ReviewAction, "id" | "key" | "label">[],
	width: number,
	prefixWidth: number,
): { id: ReviewActionId; x: number; width: number }[][] {
	const gap = 2;
	const rows: { id: ReviewActionId; x: number; width: number }[][] = [[]];
	let x = Math.max(0, prefixWidth);
	for (const action of actions) {
		const buttonWidth = visibleWidth(buttonFace(action.key, action.label, false));
		const row = rows[rows.length - 1]!;
		if (row.length > 0 && x + buttonWidth > width) {
			rows.push([]);
			x = 1;
		}
		rows[rows.length - 1]!.push({ id: action.id, x, width: buttonWidth });
		x += buttonWidth + gap;
	}
	return rows;
}

function paintActionBar(
	actions: ReviewAction[],
	theme: Theme,
	hoverId: ReviewActionId | undefined,
	width: number,
	originY: number,
	prefix: string,
): { lines: string[]; hits: ButtonHit[] } {
	const placed = planActionRows(actions, width, visibleWidth(prefix));
	const byId = new Map(actions.map((action) => [action.id, action]));
	const lines: string[] = [];
	const hits: ButtonHit[] = [];
	placed.forEach((row, rowIndex) => {
		const parts: string[] = [];
		let cursor = 0;
		if (rowIndex === 0 && prefix) {
			parts.push(theme.fg("dim", prefix));
			cursor = visibleWidth(prefix);
		}
		for (const spot of row) {
			if (spot.x > cursor) parts.push(" ".repeat(spot.x - cursor));
			const action = byId.get(spot.id)!;
			const hovered = hoverId === action.id;
			parts.push(paintActionButton(action, theme, hovered));
			hits.push({ id: action.id, y: originY + rowIndex, x: spot.x, width: spot.width, enabled: action.enabled });
			cursor = spot.x + spot.width;
		}
		lines.push(parts.join(""));
	});
	return { lines, hits };
}

function paintActionButton(action: ReviewAction, theme: Theme, hovered: boolean): string {
	const face = buttonFace(action.key, action.label, hovered && action.enabled);
	if (!action.enabled) return theme.style(face, hovered ? { fg: "muted", underline: true } : { fg: "dim" });
	if (action.pending || hovered) return theme.style(face, { fg: action.pending ? "warning" : "accent", bg: "selectedBg", bold: true, underline: true });
	return theme.style(face, { fg: action.tone, bg: "customMessageBg" });
}
