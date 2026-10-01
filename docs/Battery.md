# Battery

How charge history, capacity and the charge limit work on the Kompakt. With our
kernel and vendor, the charge limit, the cycle count and the design capacity all
work.

## 1. Who owns what

```
kernel  mtk_battery.c            the power_supply "battery" node
kernel  battery_monitor.c        /sys/kernel/battery_monitor/*, RAM only
vendor  libkompakthealth.so      coulomb counting, persistence, limit enforcement
vendor  ...health@2.0-impl-2.1-kompakt.so   the HAL the AOSP health service loads
```

`battery_monitor` is a RAM store of nine nodes and persists nothing. The vendor
HAL writes everything durable to `/mnt/vendor/persist/battery/` as
`<value>:<crc32>` in A/B slots, with a last-known-good copy and an atomic
tmp + rename + fsync. The cycle count lives in the persist partition, so it
survives reinstalling the system.

Bounds the HAL enforces: 0-10000 cycles, 0-57600 on the charge sum, and a
fallback design capacity of 2946000 uAh.

## 2. Nodes

Under `/sys/kernel/battery_monitor/`, owned by `system`:

| node | access | meaning |
| --- | --- | --- |
| `cycle_counter` | rw | full-charge equivalents, maintained by the HAL |
| `first_use_date` | rw | set once, on first boot |
| `first_use_predicted_date` | rw | HAL estimate |
| `first_use_trigger` | rw | asks the HAL to stamp the date |
| `hwks_on_boot` | r | kill-switch position latched at boot |
| `extra_data` | rw | opaque HAL blob, up to 3072 bytes, no recoverable format |
| `extra_trigger` | rw | asks the HAL to refill `extra_data` |
| `charge_limit` | rw | 50-100, clamped by the driver |
| `hysteresis_enable` | rw | resume threshold behaviour |

**Access.** KompaktService runs as uid `system` in `system_app`, and vendor
policy grants `system_app` every node, so the app reads the history and sets the
limit directly. Our vendor also lets `shell` read them for diagnosis
(`vendor/scripts/apply-battery-access.sh`: `chmod 0644` in `init.project.rc` and
seven `allow shell_31_0 ... (file (read getattr open))` lines). Writes stay with
`system`.

## 3. Charge limit

Write 50-100 to `charge_limit`. The vendor HAL enforces it by writing `"0 0\n"`
or `"0 1\n"` to `/proc/mtk_battery_cmd/current_cmd`. At 100 it uses hysteresis
instead of a hard stop: stop at 100, resume at 95. It does nothing when
`ro.bootmode` is `charger` (off-mode charging).

It depends on the SELinux fix in section 5: on Mudita's vendor under a GSI the
HAL cannot open `/proc/mtk_battery_cmd`.

## 4. What the kernel reports

What is measured and what is a constant:

| property | value | source |
|---|---|---|
| `cycle_count` | real | `battery_monitor_get_cycle_count()`, the HAL's `cycle_counter` |
| `capacity` | real | the gauge's state of charge |
| `charge_counter` | derived | `capacity` % of `charge_full` |
| `charge_full` | 2946000, fixed | MediaTek boilerplate `g_Q_MAX`, never learned |
| `charge_full_design` | 3000000, fixed | `KOMPAKT_DESIGN_CAPACITY_MAH` |
| health | about 98%, fixed | 2946 / 3000; this gauge does not learn capacity |

Kernel patch 0020 carries two fixes to Mudita's `mtk_battery.c`. Under
Mudita's stock kernel `charge_full_design` reads 294000 (Android shows ~1002%
health) and `cycle_count` reads 1.

- **Design capacity.** Mudita's code divided `q_max` by ten for
  `CHARGE_FULL_DESIGN` only; `CHARGE_FULL` and `CHARGE_COUNTER` treat the same
  value as mAh. It is now the constant `KOMPAKT_DESIGN_CAPACITY_MAH` (3000).
  It cannot be a `module_param`: `MODULE` is defined for this translation unit
  though the object is built in, and `vmlinux` fails to link on
  `__this_module`. The `/ 10` in `TIME_TO_FULL_NOW` is correct and stays: it
  absorbs the gauge's 0.1 mA unit.
- **Cycle count.** Mudita's code returned 1. The HAL maintains a real count,
  but `UpdateHealthInfo()` in Mudita's library is an empty function, so it never
  reached Android. The kernel now reports `battery_monitor_get_cycle_count()`,
  exported by `battery_monitor.c`; `mtk_battery.c` has a weak fallback
  returning -1 in case the monitor is configured out. healthd reads
  `/sys/class/power_supply/battery/cycle_count`, so no vendor change is needed.

**Where 3000 comes from.** No capacity is stated in either tree. On disk:

1. **3037 mAh**: `dts/kompakt-base.dts`, node `mtk_gauge`,
   `battery0_profile_t0` to `t5`. Six 100-row OCV tables (units 0.1 mAh,
   0.1 mV, 0.1 mOhm) spanning 0 to 30370 from 4.337 V down to 3.020 V. This is a
   characterization of the Kompakt cell and is in use: the live table ends
   `(99,30370,30200,5900,10617)`. MediaTek's reference tables span 0 to 29760
   from 4.328 V, a different cell.
2. **2860 mAh**: `qmax_t_0ma 28603`, capacity to the 3.35 V system cutoff:
   usable, not nominal.
3. **2946 mAh**: stock MediaTek `g_Q_MAX[T0][bat1]` from
   `mtk_battery_table.h`. The DTS has no `g_Q_MAX`, so the driver falls back to
   the compiled-in array (the bootloader log says `Get g_Q_MAX failed`). Not
   evidence.

A cell characterizing at 3037 mAh to 3.0 V is a 3000 mAh-class part.

## 5. SELinux: orphaned vendor types

`vendor/etc/selinux/plat_pub_versioned.cil` declares each vendor public type
like this:

```
(type proc_battery_cmd)
(typeattribute proc_battery_cmd_31_0)
(roletype object_r proc_battery_cmd_31_0)
(genfscon proc /mtk_battery_cmd (u object_r proc_battery_cmd ((s0) (s0))))
```

The line binding the attribute to the type,
`(typeattributeset proc_battery_cmd_31_0 (proc_battery_cmd))`, is missing. The
node carries the concrete type, every rule names the empty attribute, and the
rules match nothing:

```
avc: denied { search } comm="health@2.1-serv" name="mtk_battery_cmd"
  scontext=u:r:hal_health_default:s0 tcontext=u:object_r:proc_battery_cmd:s0
```

Core AOSP types are bound by the system side (`mapping/31.0.cil`). What remains
are 31 MediaTek and Mudita types that nothing binds:

```
aee_core_forwarder capability_app cmddumper connsyslogger em_app emdlogger
em_svr mdlogger mobile_log_d mtd_device mtk_advcamserver mtkbootanimation
mudita_service netdiag proc_battery_cmd proc_battery_current_cmd sysfs_headset
sysfs_pmu sysfs_vbus teeregistryd_app vtservice
+ 9 system_mtk_*_prop
```

`vendor/scripts/fix-orphaned-vendor-types.sh` adds one `typeattributeset` line
for each (`associations_added=31` on a fresh stage), which also fixes the role
error (`Type proc_battery_current_cmd is invalid for role object_r`) in a
full-policy compile. It also grants `init` `setattr` on `sysfs_eink_misc` and
`sysfs_eink_param`, so the e-ink `chmod`s in `init.project.rc` take effect.

Nothing fails at boot without these lines: the policy loads and the affected
features quietly do nothing. A rule against an empty attribute compiles and
grants nothing, so do not take "the policy compiled" as proof. Check the device:
`ls -Z` the node, and `logcat -b all | grep 'avc:  denied'`.

Vendor-private types declared in `vendor_sepolicy.cil` (such as our e-ink
types) are not versioned and are not affected.

## 6. Dead code in the vendor HAL

`BatteryDefender`, `BatteryThermalControl`, `ChargerDetect` and `DeviceHealth`
exist in `libkompakthealth.so` and none of them run: the impl `.so` imports
exactly two symbols from it. Do not read behaviour from those classes.
