// SPDX-License-Identifier: GPL-2.0
/*
 * Kompakt e-ink shim: replaces meink.ko's callback table (registration is
 * last-wins), forwards every call to it and traces the driver API.
 * Load after meink.ko, before anything drives the panel.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/printk.h>

#include "../mudita/eink_loader/eink_hal.h"

/* On by default: the sysfs switch is not reachable without root. */
static int trace = 1;
module_param(trace, int, 0644);
MODULE_PARM_DESC(trace, "log every call made through the e-ink callback table");

/* meink's table, captured at init. */
static const EinkCallbackTable_t *blob;

#define T(fmt, ...) \
	do { if (trace) pr_info("kompakt-eink: " fmt "\n", ##__VA_ARGS__); } while (0)

/* meink may leave slots NULL, so check before forwarding. */
#define FWD(slot, call, ret_on_null) \
	(blob && blob->slot ? (blob->call) : (ret_on_null))

static int k_init(EinkHndl_t *eink, void *commHndl)
{
	T("init");
	return FWD(init, init(eink, commHndl), -ENODEV);
}

static int k_deinit(EinkHndl_t *eink)
{
	T("deinit");
	return FWD(deinit, deinit(eink), -ENODEV);
}

static int k_wakeup(EinkHndl_t const eink)
{
	T("wakeup");
	return FWD(wakeup, wakeup(eink), -ENODEV);
}

static int k_sleep(EinkHndl_t const eink)
{
	T("sleep");
	return FWD(sleep, sleep(eink), -ENODEV);
}

static int k_powerOff(EinkHndl_t const eink, int state)
{
	T("powerOff state=%d", state);
	return FWD(powerOff, powerOff(eink, state), -ENODEV);
}

static int k_clearScreen(EinkHndl_t const eink, enum EInkFillPattern pattern,
			 unsigned int restoreFrame)
{
	T("clearScreen pattern=%d restore=%u", pattern, restoreFrame);
	return FWD(clearScreen, clearScreen(eink, pattern, restoreFrame), -ENODEV);
}

static int k_writeImage(EinkHndl_t const eink, unsigned char *image)
{
	T("writeImage");
	return FWD(writeImage, writeImage(eink, image), -ENODEV);
}

static int k_writeImagePart(EinkHndl_t const eink, unsigned char *image,
			    EinkImagePart_t src, EinkImagePart_t dst)
{
	T("writeImagePart src=(%u,%u %ux%u) dst=(%u,%u %ux%u)",
	  src.offset.x, src.offset.y, src.width, src.height,
	  dst.offset.x, dst.offset.y, dst.width, dst.height);
	return FWD(writeImagePart, writeImagePart(eink, image, src, dst), -ENODEV);
}

static int k_refreshScreen(EinkHndl_t const eink)
{
	T("refreshScreen");
	return FWD(refreshScreen, refreshScreen(eink), -ENODEV);
}

static int k_getBpp(EinkHndl_t const eink, unsigned int *bpp)
{
	return FWD(getBpp, getBpp(eink, bpp), -ENODEV);
}

static int k_setBpp(EinkHndl_t const eink, unsigned int bpp)
{
	T("setBpp %u", bpp);
	return FWD(setBpp, setBpp(eink, bpp), -ENODEV);
}

static int k_getWaveformMode(EinkHndl_t const eink, enum EInkWaveformType *mode)
{
	return FWD(getWaveformMode, getWaveformMode(eink, mode), -ENODEV);
}

static int k_setWaveformType(EinkHndl_t const eink, enum EInkWaveformType type)
{
	T("setWaveformType %d", type);
	return FWD(setWaveformType, setWaveformType(eink, type), -ENODEV);
}

static const char *k_getWaveformModeName(enum EInkWaveformType type)
{
	return blob && blob->getWaveformModeName ?
		blob->getWaveformModeName(type) : "";
}

static enum EInkWaveformType k_decodeWaveformModeName(const char *name)
{
	return blob && blob->decodeWaveformModeName ?
		blob->decodeWaveformModeName(name) : kEinkWaveformInvalid;
}

static int k_setTconTimingsMode(EinkHndl_t const eink, enum EInkTimingsMode mode)
{
	T("setTconTimingsMode %d", mode);
	return FWD(setTconTimingsMode, setTconTimingsMode(eink, mode), -ENODEV);
}

static int k_getTconTimingsMode(EinkHndl_t const eink, enum EInkTimingsMode *t)
{
	return FWD(getTconTimingsMode, getTconTimingsMode(eink, t), -ENODEV);
}

static const char *k_getTconTimingsModeName(enum EInkTimingsMode type)
{
	return blob && blob->getTconTimingsModeName ?
		blob->getTconTimingsModeName(type) : "";
}

static enum EInkTimingsMode k_decodeTconTimingsModeName(const char *name)
{
	return blob && blob->decodeTconTimingsModeName ?
		blob->decodeTconTimingsModeName(name) : kEinkTimingsUnknown;
}

static enum EInkRefreshMode k_decodeRefreshModeName(const char *name)
{
	return blob && blob->decodeRefreshModeName ?
		blob->decodeRefreshModeName(name) : kEinkRefreshInvalid;
}

static const char *k_getRefreshModeName(enum EInkRefreshMode mode)
{
	return blob && blob->getRefreshModeName ?
		blob->getRefreshModeName(mode) : "";
}

static int k_getRefreshMode(EinkHndl_t const eink, enum EInkRefreshMode *mode)
{
	return FWD(getRefreshMode, getRefreshMode(eink, mode), -ENODEV);
}

static int k_setRefreshMode(EinkHndl_t const eink, enum EInkRefreshMode mode)
{
	T("setRefreshMode %d", mode);
	return FWD(setRefreshMode, setRefreshMode(eink, mode), -ENODEV);
}

static enum EInkState k_getState(EinkHndl_t const eink)
{
	return blob && blob->getState ? blob->getState(eink) : kEinkStateInvalid;
}

static int k_getUpdateMode(EinkHndl_t const eink, enum EInkUpdateMode *mode)
{
	return FWD(getUpdateMode, getUpdateMode(eink, mode), -ENODEV);
}

static int k_getDisplayShape(EinkHndl_t const eink, struct EinkDisplayShape *shape)
{
	return FWD(getDisplayShape, getDisplayShape(eink, shape), -ENODEV);
}

static int k_setContrast(EinkHndl_t const eink, unsigned char contrast)
{
	T("setContrast %u", contrast);
	return FWD(setContrast, setContrast(eink, contrast), -ENODEV);
}

static int k_getContrast(EinkHndl_t const eink, unsigned char *contrast)
{
	return FWD(getContrast, getContrast(eink, contrast), -ENODEV);
}

static int k_setBrightness(EinkHndl_t const eink, unsigned char level)
{
	T("setBrightness %u", level);
	return FWD(setBrightness, setBrightness(eink, level), -ENODEV);
}

static int k_getBrightness(EinkHndl_t const eink, unsigned char *level)
{
	return FWD(getBrightness, getBrightness(eink, level), -ENODEV);
}

static int k_setGammaCorrection(EinkHndl_t const eink,
				enum EInkGammaCorrectionLevel level)
{
	T("setGammaCorrection %d", level);
	return FWD(setGammaCorrection, setGammaCorrection(eink, level), -ENODEV);
}

static int k_getGammaCorrection(EinkHndl_t const eink,
				enum EInkGammaCorrectionLevel *level)
{
	return FWD(getGammaCorrection, getGammaCorrection(eink, level), -ENODEV);
}

static int k_getDitheringParameter(EinkHndl_t const eink, int *value)
{
	return FWD(getDitheringParameter, getDitheringParameter(eink, value), -ENODEV);
}

static int k_setDitheringParameter(EinkHndl_t const eink, int value)
{
	T("setDitheringParameter %d", value);
	return FWD(setDitheringParameter, setDitheringParameter(eink, value), -ENODEV);
}

static int k_getDitheringType(EinkHndl_t const eink, enum EInkDitheringType *type)
{
	return FWD(getDitheringType, getDitheringType(eink, type), -ENODEV);
}

/* A dither_colors write makes the loader force FloydSteinbergOpt1 here. */
static int k_setDitheringType(EinkHndl_t const eink, enum EInkDitheringType type)
{
	T("setDitheringType %d%s", type,
	  type == kEinkDitheringTypeFloydSteinbergOpt1 ?
		" (may be dither_colors forcing it)" : "");
	return FWD(setDitheringType, setDitheringType(eink, type), -ENODEV);
}

static int k_getTemperatureCorrection(EinkHndl_t const eink, int *correction)
{
	return FWD(getTemperatureCorrection, getTemperatureCorrection(eink, correction), -ENODEV);
}

/* The correction shifts the waveform temperature band, 3 degrees C per band. */
static int k_setTemperatureCorrection(EinkHndl_t const eink, int correction)
{
	T("setTemperatureCorrection %d (shifts the waveform band)", correction);
	return FWD(setTemperatureCorrection, setTemperatureCorrection(eink, correction), -ENODEV);
}

static int k_getTemperature(EinkHndl_t const eink, int *temperature)
{
	int ret = FWD(getTemperature, getTemperature(eink, temperature), -ENODEV);

	if (!ret && temperature)
		T("getTemperature %d -> band %d", *temperature, *temperature / 3);
	return ret;
}

static int k_enableManualMode(EinkHndl_t const eink, unsigned int enable)
{
	T("enableManualMode %u", enable);
	return FWD(enableManualMode, enableManualMode(eink, enable), -ENODEV);
}

static int k_getManualMode(EinkHndl_t const eink, unsigned int *enable)
{
	return FWD(getManualMode, getManualMode(eink, enable), -ENODEV);
}

static void k_setFpsLimit(unsigned int fps)
{
	T("setFpsLimit %u", fps);
	if (blob && blob->setFpsLimit)
		blob->setFpsLimit(fps);
}

static int k_getFpsLimit(void)
{
	return blob && blob->getFpsLimit ? blob->getFpsLimit() : 0;
}

static const EinkCallbackTable_t kompakt_table = {
	.init			= k_init,
	.deinit			= k_deinit,
	.wakeup			= k_wakeup,
	.sleep			= k_sleep,
	.powerOff		= k_powerOff,
	.clearScreen		= k_clearScreen,
	.writeImage		= k_writeImage,
	.writeImagePart		= k_writeImagePart,
	.refreshScreen		= k_refreshScreen,
	.getBpp			= k_getBpp,
	.setBpp			= k_setBpp,
	.getWaveformMode	= k_getWaveformMode,
	.setWaveformType	= k_setWaveformType,
	.getWaveformModeName	= k_getWaveformModeName,
	.decodeWaveformModeName	= k_decodeWaveformModeName,
	.setTconTimingsMode	= k_setTconTimingsMode,
	.getTconTimingsMode	= k_getTconTimingsMode,
	.getTconTimingsModeName	= k_getTconTimingsModeName,
	.decodeTconTimingsModeName = k_decodeTconTimingsModeName,
	.decodeRefreshModeName	= k_decodeRefreshModeName,
	.getRefreshModeName	= k_getRefreshModeName,
	.getRefreshMode		= k_getRefreshMode,
	.setRefreshMode		= k_setRefreshMode,
	.getState		= k_getState,
	.getUpdateMode		= k_getUpdateMode,
	.getDisplayShape	= k_getDisplayShape,
	.setContrast		= k_setContrast,
	.getContrast		= k_getContrast,
	.setBrightness		= k_setBrightness,
	.getBrightness		= k_getBrightness,
	.setGammaCorrection	= k_setGammaCorrection,
	.getGammaCorrection	= k_getGammaCorrection,
	.getDitheringParameter	= k_getDitheringParameter,
	.setDitheringParameter	= k_setDitheringParameter,
	.getDitheringType	= k_getDitheringType,
	.setDitheringType	= k_setDitheringType,
	.getTemperatureCorrection = k_getTemperatureCorrection,
	.setTemperatureCorrection = k_setTemperatureCorrection,
	.getTemperature		= k_getTemperature,
	.enableManualMode	= k_enableManualMode,
	.getManualMode		= k_getManualMode,
	.setFpsLimit		= k_setFpsLimit,
	.getFpsLimit		= k_getFpsLimit,
};

static int __init kompakt_eink_init(void)
{
	blob = eink_getCallback();
	if (!blob) {
		/* meink.ko not loaded: a table forwarding nowhere would freeze the panel. */
		pr_err("kompakt-eink: no callback table registered yet, load after meink.ko\n");
		return -EAGAIN;
	}
	if (blob == &kompakt_table) {
		pr_err("kompakt-eink: already installed\n");
		return -EBUSY;
	}

	eink_registerCallbackTable(&kompakt_table);
	pr_info("kompakt-eink: installed over %ps, trace=%d\n", blob, trace);
	return 0;
}

static void __exit kompakt_eink_exit(void)
{
	/* Hand the panel back before we go, or the next call is into freed text. */
	if (blob)
		eink_registerCallbackTable(blob);
	pr_info("kompakt-eink: removed\n");
}

module_init(kompakt_eink_init);
module_exit(kompakt_eink_exit);

MODULE_DESCRIPTION("Kompakt e-ink shim over meink.ko");
MODULE_LICENSE("GPL v2");
MODULE_SOFTDEP("pre: meink");
