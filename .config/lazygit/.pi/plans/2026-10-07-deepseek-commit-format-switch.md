为 DeepSeek 提交生成增加无 emoji 默认格式和独立 Gitmoji 快捷键，并在 lazygit 输入框内编辑后提交。

修改 config.yml 和 deepseek-commit：
- 脚本默认输出三个 `<type>(<scope>): <summary>` 候选，新增 --gitmoji 保留原有 emoji 格式。保留 API 和重试，校验对应响应字段。脚本只输出候选。
- Ctrl+G 默认无 emoji，Ctrl+T Gitmoji。使用 lazygit 0.65.1 的 menuFromCommand 选择候选，再用 initialValue 预填 input。编辑确认后用 quote 安全传给 git commit -m，Esc 取消。

验证 shell 语法、配置、临时仓库和模拟 API 下的两种格式、失败处理。尽可能通过终端自动化验证菜单、编辑、取消与最终提交；明确真实 API 或交互验证限制。
