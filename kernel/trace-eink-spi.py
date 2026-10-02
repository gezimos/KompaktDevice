#!/usr/bin/env python3
"""Add an SPI trace to eink_spi_hal.c (enable with einktrace.trace=1). See docs/E-inkdriver.md.

Usage: trace-eink-spi.py <kernel source dir>
"""
import os, re, sys

P = os.path.join(sys.argv[1], "drivers/misc/mudita/eink_loader/eink_spi_hal.c")
s = open(P).read()

# The tracer, placed after the includes.
anchor = "int eink_registerCallbackTable(const EinkCallbackTable_t* cbTable)"
assert s.count(anchor) == 1, "anchor"

tracer = '''/*
 * Kompakt: a trace of everything the panel is told.
 *
 * meink.ko is proprietary, but it reaches the panel only through this file, so
 * every command it issues can be recorded here. Dump with:
 *     dmesg | grep einkspi
 * Each line is direction, byte count, then up to TRACE_BYTES bytes. Image
 * payloads are long and are truncated; the commands that matter are short.
 */
static int trace;
module_param(trace, int, 0644);
MODULE_PARM_DESC(trace, "log every SPI transfer to and from the panel");

#define TRACE_BYTES 32

static void eink_trace(const char *dir, const void *buf, unsigned int size)
{
    unsigned int n = size < TRACE_BYTES ? size : TRACE_BYTES;
    char hex[TRACE_BYTES * 3 + 1];
    const unsigned char *p = buf;
    unsigned int i;

    if (!trace)
        return;

    for (i = 0; i < n; i++)
        scnprintf(hex + i * 3, 4, "%02x ", p[i]);
    hex[n ? n * 3 - 1 : 0] = '\\0';

    pr_info("einkspi %s len=%u %s%s\\n", dir, size, hex,
            size > n ? " ..." : "");
}

'''
s = s.replace(anchor, tracer + anchor, 1)

# Writes: log before the transfer, so a hang still leaves the command.
old = """    gTestLastStep = ktime_get();
    retVal = spi_write(spi, buf, size);"""
new = """    eink_trace("w", buf, size);
    gTestLastStep = ktime_get();
    retVal = spi_write(spi, buf, size);"""
assert s.count(old) == 1, "write site"
s = s.replace(old, new)

# Reads: log after the transfer.
old = """    eink_waitForReady(hw);
    retVal = spi_read(spi, buf, size);
    return retVal;"""
new = """    eink_waitForReady(hw);
    retVal = spi_read(spi, buf, size);
    if (retVal >= 0)
        eink_trace("r", buf, size);
    return retVal;"""
assert s.count(old) == 1, "read site"
s = s.replace(old, new)

# Power sequence.
old = """    msleep(10);
    gpio_set_value(hw->gpio.pin_3v3_num, 1);"""
new = """    if (trace)
        pr_info("einkspi power-up: 3v3 on, reset low, reset high\\n");
    msleep(10);
    gpio_set_value(hw->gpio.pin_3v3_num, 1);"""
assert s.count(old) == 1, "power site"
s = s.replace(old, new)

open(P, "w").write(s)
print("TRACE157 OK")
