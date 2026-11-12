#pragma once

#include <cstdint>
#include <cmath>

// Offline punch queue. kind: 0 empty, 1 clock in, 2 clock out.
// Slots are in press order. HA replays them when the API is back.

struct AttendanceView {
  uint32_t in_ts;
  uint32_t out_ts;
  bool open_in;
  bool closed_out;
};

inline int attendance_count(const uint8_t *kind) {
  int n = 0;
  while (n < 4 && kind[n] != 0) {
    n++;
  }
  return n;
}

inline AttendanceView attendance_view(const uint8_t *kind, const uint32_t *ts) {
  AttendanceView view{0, 0, false, false};
  for (int i = 0; i < 4; i++) {
    if (kind[i] == 0) {
      break;
    }
    if (kind[i] == 1) {
      view.in_ts = ts[i];
      view.out_ts = 0;
      view.open_in = true;
      view.closed_out = false;
    } else if (kind[i] == 2) {
      view.out_ts = ts[i];
      view.open_in = false;
      view.closed_out = true;
    }
  }
  return view;
}

inline bool attendance_enqueue(uint8_t kind, uint8_t *kinds, uint32_t *ts, uint32_t now_ts, bool ha_shift_open) {
  if (now_ts < 1000000000UL) {
    return false;
  }
  if (kind != 1 && kind != 2) {
    return false;
  }
  int last = attendance_count(kinds) - 1;
  if (kind == 1) {
    if (last >= 0 && kinds[last] == 1) {
      return false;
    }
    if (last < 0 && ha_shift_open) {
      return false;
    }
  } else {
    if (last >= 0 && kinds[last] == 2) {
      return false;
    }
    bool local_open = last >= 0 && kinds[last] == 1;
    if (!local_open && !ha_shift_open) {
      return false;
    }
  }
  if (last >= 3) {
    return false;
  }
  int slot = last + 1;
  kinds[slot] = kind;
  ts[slot] = now_ts;
  return true;
}

inline void attendance_pop(uint8_t *kinds, uint32_t *ts) {
  for (int i = 0; i < 3; i++) {
    kinds[i] = kinds[i + 1];
    ts[i] = ts[i + 1];
  }
  kinds[3] = 0;
  ts[3] = 0;
}

// Home Assistant exposes the timestamp as a float. Around 2026 a float
// cannot tell seconds apart, so the match window is wider than one minute.
inline bool attendance_matches(uint8_t kind, uint32_t ts, bool in_set, float in_ts, bool out_set, float out_ts) {
  const float tolerance = 180.0f;
  if (kind == 1 && in_set && in_ts == in_ts && fabsf(in_ts - static_cast<float>(ts)) < tolerance) {
    return true;
  }
  if (kind == 2 && out_set && out_ts == out_ts && fabsf(out_ts - static_cast<float>(ts)) < tolerance) {
    return true;
  }
  return false;
}

// Drop the head punch when Home Assistant will not accept another copy of it.
// A clock-in behind an already-open shift used to sit at the head forever and
// block the clock-out behind it. Unknown shift flags are not a reason to drop.
inline bool attendance_drop_head(uint8_t kind, uint32_t ts, bool in_known, bool in_set, float in_ts, bool out_known, bool out_set, float out_ts) {
  if (kind != 1 && kind != 2) {
    return true;
  }
  if (!in_known || !out_known) {
    return false;
  }
  if (attendance_matches(kind, ts, in_set, in_ts, out_set, out_ts)) {
    return true;
  }
  bool shift_open = in_set && !out_set;
  if (kind == 1 && shift_open) {
    return true;
  }
  if (kind == 2 && !shift_open) {
    return true;
  }
  return false;
}
