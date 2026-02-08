# system_profiler.sh — Issues Found

## The ARM Variable Assignment (Not Actually Broken)

The `cpu_model=$(...)` pattern on lines 36–41 is **not** a subshell scoping issue.
`var=$(command)` runs the command in a subshell but assigns the result in the **current
shell**. The variable is available afterward. No fix needed.

The *actual* subshell-loses-variables pattern is `command | while read ...; do var=x; done`
(piping into a loop). That pattern *does* appear in this script (lines 106, 115, 204), but
those loops only `echo` — they never set variables that need to persist, so they're fine too.

---

## Real Issues

### 1. ARM CPU Part is a Hex Code, Not a Name (Line 42)

`CPU part` from `/proc/cpuinfo` returns a raw hex value like `0xd08`, not a human-readable
core name. The string built on line 42:

```
"$cpu_model (Cortex-$cpu_part, $cpu_implementer, ARMv$cpu_arch)"
```

produces something like `Raspberry Pi 5 (Cortex-0xd0b, 0x41, ARMv8)` instead of
`Raspberry Pi 5 (Cortex-A76, ARM, ARMv8)`.

Both `cpu_part` and `cpu_implementer` need a lookup table to map hex to names:
- `0xd03` → Cortex-A53
- `0xd08` → Cortex-A72
- `0xd0b` → Cortex-A76
- `0x41` (implementer) → ARM

### 2. Integer Comparison Without Validation (Line 155)

```bash
if [ "$zone_temp" -gt 1000 ]; then
```

If `zone_temp` is empty or non-numeric (e.g., a read failure), this will produce a bash
error: `integer expression expected`. Should guard with a numeric check first:

```bash
if [ -n "$zone_temp" ] && [ "$zone_temp" -gt 1000 ] 2>/dev/null; then
```

### 3. Intel GPU Detection Counts All GPUs (Line 228)

```bash
intel_gpus=$(ls /sys/class/drm/ 2>/dev/null | grep -c "card[0-9]$" || echo 0)
```

`/sys/class/drm/card*` lists **all** DRM graphics cards, not just Intel. An NVIDIA or AMD
GPU would also appear as `card0`, `card1`, etc. This section would falsely label any GPU as
an Intel GPU. Should check the driver or vendor ID to confirm Intel.

### 4. Dependency on `bc` Without Fallback (Lines 62, 156)

```bash
freq_ghz=$(echo "$freq_hz/1000000" | bc -l 2>/dev/null | awk '...')
zone_temp=$(echo "$zone_temp / 1000" | bc 2>/dev/null || echo "$zone_temp")
```

`bc` is not guaranteed on minimal or container environments. The frequency line silently
fails to "Unknown" (acceptable), but the temperature line falls back to printing
millidegrees as if they were degrees — `49000°C` instead of `49°C`. Use `awk` as a
portable alternative:

```bash
zone_temp=$(awk "BEGIN {printf \"%.0f\", $zone_temp / 1000}")
```

### 5. Useless Use of Cat (Lines 39–41, 50, 67)

```bash
cpu_part=$(cat /proc/cpuinfo 2>/dev/null | grep "CPU part" | ...)
```

Should be:

```bash
cpu_part=$(grep "CPU part" /proc/cpuinfo 2>/dev/null | head -1 | ...)
```

Saves a process and is more idiomatic. Applies to five lines in the script.

### 6. macOS Storage Loop Inconsistency (Lines 92–94 vs 97)

The macOS path uses `while read` in a pipe:
```bash
df -h | grep -E "^/dev/" | head -5 | while read line; do
    echo "  $line"
done
```

While the Linux path uses `sed`:
```bash
df -h | grep -E "^/dev/" | head -5 | sed 's/^/  /'
```

Both work, but the macOS version uses an unnecessary subshell loop where `sed` would suffice
identically. Not a bug, but inconsistent.

### 7. `ip addr show` Interface Parsing Is Fragile (Lines 106–108)

```bash
iface=$(echo "$line" | cut -d':' -f2 | sed 's/^ *//')
```

VLAN interfaces can contain colons in their names (e.g., `eth0.100@eth0`), and `cut -d':'`
would split incorrectly. Also, interface names with `@` aliases (like `veth` pairs) may
confuse the subsequent `ip addr show "$iface"` call.
