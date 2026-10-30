// Direct numeric reuse: 网页视频实时 LUT, @author You, @version 6.7.8. No license inferred.
var OriginalLUT = (function(){
const console = {log:function(){},warn:function(){},error:function(){}};
    const CONFIG = {
        lutSize: 33,
        analysisLongSide: 640,
        autoReanalyze: false,
        reanalyzeInterval: 300000,
        initialDelayMs: 500,
        defaultEnabled: true,
        maxSkinPixels: 3000,
        sampleFrames: 3,
        sampleIntervalMs: 120,
        mediapipeVersion: '0.10.14',
        mediapipeModelUrl: 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task',
        faceBoxExpand: 1.0,
        pollIntervalMs: 500,
        debugFaceBox: false,
        preloadMediaPipe: true,
        coarseSampleSize: 400,
        enableStatsCache: true,
        lumGuardTolerance: 0.005,
        balanceParams: true,
        paramStrength: {
            temp: 0.6,
            highlight: 0.3,
            shadow: 0.6,
            contrast: 0.4,
        },
        balanceMultiplier: 1.0,
        analyzeRetryCooldownMs: 3000,
        canvasMatchVideo: 1,
        canvasResizeThreshold: 4,
        severeSatThreshold: 0.45,
        severeSatMin: -15,
        autoHlCompBrightThreshold: 15,
        autoHlCompStrength: 0.5,
        autoHlCompMinOrigHl: 0.01,
        nearWhiteDelta: 0.08,
        nearWhiteMinC: 0.85,
        brightGuardMaxAdd: 2,
        highlightGuardMaxAdd: 1,
        singleFrameTimeoutMs: 500,
        minSkinPixels: 150,
        faceBoxMinSkinPixels: 150,
        fullScanTargetPixels: 40000,
        skinRBHighThreshold: 999,
        highRBInherentMax: 1.15,
        highRBColorCastMin: 1.25,
        highPixelMinCount: 20,
        highLumThreshold: 0.7,
        highFallbackLumThreshold: 0.8,
        highFallbackSatMax: 0.15,
        inherentYellowRatio: 0.85,
        highPixelLowThreshold: 200,
        highPixelDarkSkinMax: 0.52,
        highPixelForceBright: 20,
        extraTempSatMin: 0.43,
        extraTempRBMin: 1.7,
        extraTempShadowMin: 0.018,
        extraTempHlMax: 0.04,
        extraTempStep: 2,
        extraTempMaxSteps: 25,
        extraTempSatWeight: 2,
        globalHlSampleStep: 2,
        skinDetection: {
            crCoverage: 0.90,
            fallbackCrRange: [130, 180],
            staticCbRange: [77, 127],
        },
        highHlScene: {
            hlRatioMin: 0.45,
            lumMin: 0.62,
            highRBMin: 1.25,
            hlCompMin: -18,
            highlightHardMin: -18,
            hlHiCap: 0.06,
            tempExtraMin: -10,
            contrastTargetShift: 0.05,
            contrastDevWeight: 0.0001,
            satTargetFactor: 1.05,
            satMaxExtra: 3,
            shadowMaxFactor: 0.5,
            brightMaxExtra: 5,
        },
        // Build 278: the 6.7.8 look is the target again (whos.tv stills are raw source frames, not grades).
        // Safety only engages on frames that would actually fail after the full bake pipeline,
        // measured on a whole-frame sample + the skin sample; params are nudged one step at a time
        // until the frame passes, so every other frame keeps the full 6.7.8 enhancement.
        safety: {
            enabled: true,
            maxSteps: 60,
            globalSamplePixels: 2048,
            clipLuma: 0.96, clipAddMax: 0.015,          // new near-cap pixels (OVEREXPOSE_LIMIT flattens to 0.92)
            hlLuma: 0.65, hlMinFrac: 0.03, hlDetailMin: 0.74, hlMeanMargin: 0.004, // highlight texture kept
            skinLumMax: 0.70,                          // skin washout
            darkLuma: 0.12, darkMinFrac: 0.02, darkMeanMin: 0.85, darkDetailMin: 0.85, p1DropMax: 0.02,
            p1RiseMax: 0.06,                           // blacks lifted to grey (stockings lose depth)
            magentaHue: 0, magentaExtraRot: 2, magentaMargin: 1.5,         // skin mean hue must not go below 0 deg (= >360 magenta)
            oversatAbs: 0.60, oversatRatio: 1.35,
            minSkinSat: 0.03, maxSkinSat: 0.75, minSkinLum: 0.08, hueRange: [-25, 60],
            brightFloor: 0, highlightFloor: -18, contrastFloor: -5, shadowCeil: 20, satFloor: -15,
            // Build 279 (on-device haze report): contrast / black point / high-key / pink limits
            hazeStdMin: 0.93, hazeRangeMin: 0.93,      // global luma std and p95-p5 range kept
            p5RiseMax: 0.02, dark3RiseMax: 0.02,       // black point / deepest 3% not lifted (stockings)
            whiteMinFrac: 0.02, whiteDropMax: 0.03,    // neutral whites not greyed
            highKeyP50: 0.50, highKeyRiseMax: 0.03, highKeySkinLum: 0.55, highKeySkinRiseMax: 0.03,
            pinkHue: 9, pinkRotMax: 7,                // skin rotated toward pink
            hlblowHighlightFloor: -15,
        },
        // Build 278 shadow toe: near-black keeps the black point, its own hue and a bounded slope;
        // lift is allowed (6.7.8 shadow/bright intent), crushing is not.
        shoulder: { enabled: true, knee: 0.78, ceil: 0.97 },
        shadowToe: {
            toeEnd: 0.20, toeFull: 0.08, slopeMin: 0.97, slopeMax: 1.10, slopeMaxShadow: 1.35, shadowForWide: 12,
        },
        // Build 279: bright low-saturation (white / near-white) source keeps its luminance, so
        // high-key white scenes are not greyed by the highlight pull or hazed by the shoulder.
        whiteAnchor: { enabled: true, lumLo: 0.62, lumHi: 0.80, satLo: 0.10, satHi: 0.22 },
        // Build 280 presets. Every preset runs the 279 per-frame safety gate (crush / lift / grey-white /
        // magenta / hlblow / oversat stay at the 279 limits); presets only scale the 6.7.8 params and relax
        // the purely aesthetic limits. 'standard' is exactly Build 279.
        preset: 'standard',
        presets: {
            natural: { scale: 0.75, safety: {} },
            standard: { scale: 1, safety: {} },
            // Build 280 benchmark (whos.tv held-out, 3887 frames): relaxing the high-key limits brightened 18.7 %
            // of high-key frames, so 增强 only widens the skin-rotation allowance (6.7.8's warmer skin), the haze
            // floor and the highlight-recovery floor. Black / white / magenta / high-key limits stay at 279.
            enhanced: { scale: 1, safety: { pinkRotMax: 12, hazeStdMin: 0.90, hazeRangeMin: 0.90, hlblowHighlightFloor: -18 } },
        },
    }
    const KR = 0.2126, KG = 0.7152, KB = 0.0722;
    const HL_THRESHOLD = 0.65;
    const SH_THRESHOLD = 0.20;
    const OVEREXPOSE_LIMIT = 0.92;
    const HL_BRIGHT_DAMP_START = 0.7;
    const HL_BRIGHT_DAMP_STRENGTH = 0.7;
    const HL_BRIGHT_DAMP_MIN = 0.3;
    const HL_CONTRAST_DAMP_STRENGTH = 0.5;
    const HL_CONTRAST_DAMP_MIN = 0.5;
    const FACE_SKIN_LUM_MAX = 0.9;

    // ---- 校准目标区间 ----
    const TARGETS = {
        skin_rb:       [1.24, 1.50],
        skin_rg:       [1.20, 1.35],
        skin_lum:      [0.35, 0.54],
        skin_sat:      [0.22, 0.34],
        full_contrast: [0.10, 0.20],
        full_hl_ratio: [0.00, 0.22],
        full_sh_ratio: [0.00, 0.40],
    };

    const JY_TEMPLATE = {
        temp: -20, tint: 6, sat: 0, bright: 0,
        contrast: 0, highlight: -2, shadow: 2,
    };
    const JY_ADJUST_RANGE = {
        temp: [-20, 5], tint: [-5, 5], sat: [-5, 3],
        bright: [-5, 18], contrast: [-3, 2],
        highlight: [-5, 3], shadow: [-5, 10],
    };

    const JY_TEMPLATE_HIGH_MATCH = {
        temp: -3, tint: 6, sat: 0, bright: 5,
        contrast: 0, highlight: -2, shadow: 2,
    };
    const JY_ADJUST_RANGE_HIGH_MATCH = {
        temp: [-3, -8], tint: [-5, 5], sat: [-5, 3],
        bright: [-5, 5], contrast: [-3, 2],
        highlight: [-2, 2], shadow: [-5, 5],
    };
    const TARGETS_HIGH_MATCH = {
        skin_rb:       [1.03, 1.36],
        skin_rg:       [1.10, 1.30],
        skin_lum:      [0.38, 0.62],
        skin_sat:      [0.12, 0.42],
        full_contrast: [0.12, 0.24],
        full_hl_ratio: [0.00, 0.30],
        full_sh_ratio: [0.00, 0.24],
    };

    const JY_TEMPLATE_EXTREME_DARK = {
        temp: -18, tint: 3, sat: -1, bright: 25,
        contrast: -2, highlight: -1, shadow: 20,
    };
    const JY_ADJUST_RANGE_EXTREME_DARK = {
        temp: [-10, 4], tint: [-3, 5], sat: [-5, 1],
        bright: [-15, 10], contrast: [-3, 2],
        highlight: [-3, 2], shadow: [-15, 10],
    };
    const TARGETS_EXTREME_DARK = {
        skin_rb:       [1.05, 1.32],
        skin_rg:       [1.12, 1.28],
        skin_lum:      [0.42, 0.60],
        skin_sat:      [0.14, 0.25],
        full_contrast: [0.13, 0.23],
        full_hl_ratio: [0.00, 0.30],
        full_sh_ratio: [0.14, 0.35],
    };

    // ============================================================
    // 工具函数
    // ============================================================
    function rangeError(value, targetRange) {
        const lo = targetRange[0], hi = targetRange[1];
        if (value < lo) return lo - value;
        if (value > hi) return value - hi;
        return 0.0;
    }

    function getDynamicHlTarget(skinLum) {
        const lumLo = 0.35, lumHi = 0.54;
        const hlHiAtLumLo = 0.05;
        const hlHiAtLumHi = 0.20;
        const ratio = Math.max(0, Math.min(1,
            (skinLum - lumLo) / Math.max(lumHi - lumLo, 1e-6)));
        const hlHi = hlHiAtLumLo + (hlHiAtLumHi - hlHiAtLumLo) * ratio;
        return [0.00, hlHi];
    }

    function median(arr) {
        if (!arr || arr.length === 0) return 0;
        const sorted = [...arr].sort((a, b) => a - b);
        const mid = Math.floor(sorted.length / 2);
        return sorted.length % 2
            ? sorted[mid]
            : (sorted[mid - 1] + sorted[mid]) / 2;
    }

    // 判定
    function isExtremeDark(info) {
        if (!info) return false;
        if (info.no_skin_data) return false;
        return (
            info.skin_lum < 0.28 &&
            info.full_hl_ratio < 0.01 &&
            info.full_sh_ratio > 0.24
        );
    }

    // ★ 核心修改：同步 Python 端的冷淡画面保护，并去除所有暴走后门
    function isHighMatch(info) {
        if (!info) return false;
        if (info.no_skin_data) return false;
        if (isExtremeDark(info)) return false;

        // ★ 新增：冷淡画面保护（偏冷、偏灰，避免强加亮度变惨白）
        const isColdScene = (
            info.skin_rb < 1.30 &&
            info.skin_rg < 1.30 &&
            info.skin_sat < 0.25 &&
            info.skin_lum > 0.15
        );
        if (isColdScene) {
            return true; // 直接判定为高命中，走保守模板
        }

        return (
            info.skin_rb >= TARGETS_HIGH_MATCH.skin_rb[0] &&
            info.skin_rb <= TARGETS_HIGH_MATCH.skin_rb[1] &&
            info.skin_rg >= TARGETS_HIGH_MATCH.skin_rg[0] &&
            info.skin_rg <= TARGETS_HIGH_MATCH.skin_rg[1] &&
            info.skin_lum >= TARGETS_HIGH_MATCH.skin_lum[0] &&
            info.skin_lum <= TARGETS_HIGH_MATCH.skin_lum[1] &&
            info.skin_sat >= TARGETS_HIGH_MATCH.skin_sat[0] &&
            info.skin_sat <= TARGETS_HIGH_MATCH.skin_sat[1]
        );
    }

    function subsample(pixels, maxN) {
        const n = pixels.length / 3;
        if (n <= maxN) return pixels;
        const step = n / maxN;
        const out = new Float32Array(maxN * 3);
        for (let i = 0; i < maxN; i++) {
            const s = Math.floor(i * step) * 3;
            out[i * 3] = pixels[s];
            out[i * 3 + 1] = pixels[s + 1];
            out[i * 3 + 2] = pixels[s + 2];
        }
        return out;
    }

    function isNearWhite(r, g, b) {
        const maxC = Math.max(r, g, b);
        const minC = Math.min(r, g, b);
        return (maxC - minC) < CONFIG.nearWhiteDelta && minC > CONFIG.nearWhiteMinC;
    }

    let _analyzingCount = 0;

    // 力度协调
    function _balanceParamStrength(paramsIn, template, adjustRange, useExtreme, useHighMatch,
                                    skip_bright_comp) {
        const out = Object.assign({}, paramsIn);
        const S = { temp: 0.6, highlight: 0.3, shadow: 0.6, contrast: 0.4 };
        const M = 1.0;

        const tempDelta = out.temp - template.temp;
        const tempDarken = tempDelta < 0 ? -tempDelta : 0;
        const tempEquiv = tempDarken * S.temp;

        const hlDelta = out.highlight - template.highlight;
        const hlDarken = hlDelta < 0 ? -hlDelta : 0;
        const hlEquiv = useExtreme ? 0 : hlDarken * S.highlight;

        const shDelta = out.shadow - template.shadow;
        const shDarken = shDelta < 0 ? -shDelta : 0;
        const shEquiv = shDarken * S.shadow;

        const cDelta = out.contrast - template.contrast;
        const cDarken = cDelta < 0 ? -cDelta : 0;
        const cEquiv = cDarken * S.contrast;

        const totalDarken = (tempEquiv + hlEquiv + shEquiv + cEquiv) * M;
        const brightCompensation = out.bright - template.bright;
        const deficit = totalDarken - brightCompensation;
        const _temp_at_floor = (out.temp <= -40);

        if (skip_bright_comp) {
            console.log('[LUT-算法-力度协调] 保守场景，跳过 bright 补偿');
        } else if (deficit > 0.5 && !_temp_at_floor) {
            const addBright = Math.round(deficit);
            const bMax = template.bright + adjustRange.bright[1];
            const newBright = Math.min(out.bright + addBright, bMax);
            const actualAdded = newBright - out.bright;
            out.bright = newBright;
            if (actualAdded !== 0) {
                console.log(
                    `[LUT-算法-力度协调] 压暗总量=${totalDarken.toFixed(2)}档 ` +
                    `(色温${tempEquiv.toFixed(2)}+高光${hlEquiv.toFixed(2)}+` +
                    `阴影${shEquiv.toFixed(2)}+对比度${cEquiv.toFixed(2)})，` +
                    `bright补偿=${brightCompensation.toFixed(2)}档，` +
                    `缺口=${deficit.toFixed(2)}档，实际补${actualAdded >= 0 ? '+' : ''}${actualAdded} → bright=${out.bright}`
                );
            }
            const stillDeficit = totalDarken - (out.bright - template.bright);
            if (stillDeficit > 0.5) {
                const hlMax = template.highlight + adjustRange.highlight[1];
                const hlDeficit = Math.round(stillDeficit);
                const newHl = Math.min(out.highlight + hlDeficit, hlMax);
                const actualHlAdded = newHl - out.highlight;
                if (actualHlAdded > 0) {
                    out.highlight = newHl;
                    console.log(`[LUT-算法-力度协调] bright 到顶，抬 highlight ${actualHlAdded >= 0 ? '+' : ''}${actualHlAdded} → ${newHl}`);
                }
            }
        } else if (deficit > 0.5 && _temp_at_floor) {
            console.log(`[LUT-算法-力度协调] 色温 ${out.temp} <= -40，跳过 bright 补偿（避免过曝）`);
        }

        if (!useExtreme && !useHighMatch) {
            const TEMP_FLOOR_THRESHOLD = -18;
            const BRIGHT_FLOOR_STD = 7;
            if (out.temp > TEMP_FLOOR_THRESHOLD) {
                if (out.bright < BRIGHT_FLOOR_STD) {
                    console.log(`[LUT-算法-标准模板-力度协调] 色温 ${out.temp} > ${TEMP_FLOOR_THRESHOLD}，bright ${out.bright} → ${BRIGHT_FLOOR_STD}`);
                    out.bright = BRIGHT_FLOOR_STD;
                } else {
                    console.log(`[LUT-算法-标准模板-力度协调] 色温 ${out.temp} > ${TEMP_FLOOR_THRESHOLD}，bright=${out.bright} 已 ≥ ${BRIGHT_FLOOR_STD}，不动`);
                }
            }
        }
        return out;
    }

    // ============================================================
    // 一、调色算法
    // ============================================================
    function applyTempTintScalar(r, g, b, temp, tint) {
        const t = temp / 50.0;
        const ti = tint / 50.0;
        let rGain = 1.0 + t * 0.23;
        let gGain = 1.0 + t * 0.058;
        let bGain = 1.0 - t * 0.23;
        rGain *= 1.0 + ti * 0.045;
        gGain *= 1.0 - ti * 0.09;
        bGain *= 1.0 + ti * 0.045;
        const lumBefore = KR + KG + KB;
        const lumAfter = KR * rGain + KG * gGain + KB * bGain;
        if (lumAfter > 0.001) {
            const scale = lumBefore / lumAfter;
            rGain *= scale; gGain *= scale; bGain *= scale;
        }
        const lum = KR * r + KG * g + KB * b;
        const hlStart = 0.70;
        const hlWeight = lum > hlStart
            ? Math.min(1.0, (lum - hlStart) / (1.0 - hlStart)) : 0.0;
        const protectStrength = 0.95;
        const hlDamp = 1.0 - hlWeight * protectStrength;
        const rGainEff = 1.0 + (rGain - 1.0) * hlDamp;
        const gGainEff = 1.0 + (gGain - 1.0) * hlDamp;
        const bGainEff = 1.0 + (bGain - 1.0) * hlDamp;
        return [r * rGainEff, g * gGainEff, b * bGainEff];
    }

    function applySaturationScalar(r, g, b, sat) {
        if (sat === 0) return [r, g, b];
        const gray = KR * r + KG * g + KB * b;
        const satScale = 1.0 + sat / 50.0 * 0.82;
        return [
            gray + satScale * (r - gray),
            gray + satScale * (g - gray),
            gray + satScale * (b - gray),
        ];
    }

    function applyBrightnessScalar(r, g, b, bright) {
        if (bright === 0) return [r, g, b];
        const lum = KR * r + KG * g + KB * b;
        const t = lum > HL_BRIGHT_DAMP_START
            ? (lum - HL_BRIGHT_DAMP_START) / (1.0 - HL_BRIGHT_DAMP_START) : 0.0;
        let hlDamp = 1.0 - t * HL_BRIGHT_DAMP_STRENGTH;
        hlDamp = Math.max(HL_BRIGHT_DAMP_MIN, hlDamp);

        const SHADOW_BRIGHT_DAMP_START = 0.18;
        const SHADOW_BRIGHT_DAMP_MIN = 0.35;
        let shDamp = 1.0;
        if (lum < SHADOW_BRIGHT_DAMP_START) {
            const ratio = lum / SHADOW_BRIGHT_DAMP_START;
            shDamp = SHADOW_BRIGHT_DAMP_MIN +
                (1.0 - SHADOW_BRIGHT_DAMP_MIN) * ratio;
        }

        let brightScale = 1.0 + bright / 50.0 * 0.67 * hlDamp * shDamp;

        const VERY_HIGH_LUM = 0.85;
        if (bright > 0) {
            const protectW = Math.min(1, Math.max(0,
                (lum - VERY_HIGH_LUM) / (1.0 - VERY_HIGH_LUM)));
            brightScale = brightScale * (1.0 - protectW) + 1.0 * protectW;
        }
        return [r * brightScale, g * brightScale, b * brightScale];
    }

    function applyContrastScalar(r, g, b, contrast) {
        if (contrast === 0) return [r, g, b];
        const lum = KR * r + KG * g + KB * b;
        const t = lum > HL_BRIGHT_DAMP_START
            ? (lum - HL_BRIGHT_DAMP_START) / (1.0 - HL_BRIGHT_DAMP_START) : 0.0;
        let hlDamp = 1.0 - t * HL_CONTRAST_DAMP_STRENGTH;
        hlDamp = Math.max(HL_CONTRAST_DAMP_MIN, hlDamp);
        const contrastScale = 1.0 + contrast / 50.0 * 0.57 * hlDamp;
        return [
            0.5 + contrastScale * (r - 0.5),
            0.5 + contrastScale * (g - 0.5),
            0.5 + contrastScale * (b - 0.5),
        ];
    }

    function applyHighlightShadowScalar(r, g, b, highlight, shadow) {
        if (highlight === 0 && shadow === 0) return [r, g, b];
        const lum = KR * r + KG * g + KB * b;
        if (highlight !== 0) {
            const hlW = lum > 0.5 ? (lum - 0.5) / 0.5 : 0.0;
            const hlScale = 1.0 + highlight / 50.0 * 0.7 * hlW;
            r *= hlScale; g *= hlScale; b *= hlScale;
        }
        if (shadow !== 0) {
            const shW = lum < 0.5 ? (0.5 - lum) / 0.5 : 0.0;
            const shScale = 1.0 + shadow / 50.0 * 0.7 * shW;
            r *= shScale; g *= shScale; b *= shScale;
        }
        return [r, g, b];
    }

    // 顺序：bright → hl/sh → contrast → sat → temp/tint → overexpose guard
    // Build 278: soft shoulder instead of the hard OVEREXPOSE_LIMIT plateau in the baked cube.
    function applyHighlightShoulder(r, g, b) {
        const SH = CONFIG.shoulder;
        const lum = KR * r + KG * g + KB * b;
        if (lum <= SH.knee || isNearWhite(r, g, b)) return [r, g, b];
        const span = SH.ceil - SH.knee;
        const target = SH.knee + span * (1 - Math.exp(-(lum - SH.knee) / span));
        const s = target / lum;
        return [r * s, g * s, b * s];
    }

    function applyParamsToSkinArray(pixels, params, bake) {
        const n = pixels.length / 3;
        const out = new Float32Array(n * 3);
        for (let i = 0; i < n; i++) {
            let r = pixels[i * 3];
            let g = pixels[i * 3 + 1];
            let b = pixels[i * 3 + 2];

            let t = applyBrightnessScalar(r, g, b, params.bright);
            r = t[0]; g = t[1]; b = t[2];
            t = applyHighlightShadowScalar(r, g, b, params.highlight, params.shadow);
            r = t[0]; g = t[1]; b = t[2];
            t = applyContrastScalar(r, g, b, params.contrast);
            r = t[0]; g = t[1]; b = t[2];
            t = applySaturationScalar(r, g, b, params.sat);
            r = t[0]; g = t[1]; b = t[2];
            t = applyTempTintScalar(r, g, b, params.temp, params.tint);
            r = t[0]; g = t[1]; b = t[2];

            if (bake && CONFIG.shoulder.enabled) {
                t = applyHighlightShoulder(r, g, b); r = t[0]; g = t[1]; b = t[2];
            } else {
            const lum = KR * r + KG * g + KB * b;
            if (lum > OVEREXPOSE_LIMIT && !isNearWhite(r, g, b)) {
                const s = OVEREXPOSE_LIMIT / lum;
                r *= s; g *= s; b *= s;
            }
            }
            out[i * 3] = Math.min(1, Math.max(0, r));
            out[i * 3 + 1] = Math.min(1, Math.max(0, g));
            out[i * 3 + 2] = Math.min(1, Math.max(0, b));
        }
        return out;
    }

    function sampleSkinStats(pixels) {
        const n = pixels.length / 3;
        if (n === 0) return null;
        let sR = 0, sG = 0, sB = 0, sSat = 0;
        let hl = 0, sh = 0;
        const lums = new Float32Array(n);
        for (let i = 0; i < n; i++) {
            const r = pixels[i * 3], g = pixels[i * 3 + 1], b = pixels[i * 3 + 2];
            sR += r; sG += g; sB += b;
            const lum = KR * r + KG * g + KB * b;
            lums[i] = lum;
            const max = Math.max(r, g, b), min = Math.min(r, g, b);
            sSat += max > 1e-6 ? (max - min) / max : 0;
            if (lum > HL_THRESHOLD) hl++;
            if (lum < SH_THRESHOLD) sh++;
        }
        const mR = sR / n, mG = sG / n, mB = sB / n;
        const mLum = KR * mR + KG * mG + KB * mB;
        let varSum = 0;
        for (let i = 0; i < n; i++) {
            const d = lums[i] - mLum;
            varSum += d * d;
        }
        return {
            skin_rb: mB > 1e-6 ? mR / mB : 1.0,
            skin_rg: mG > 1e-6 ? mR / mG : 1.0,
            skin_lum: mLum,
            skin_sat: sSat / n,
            full_contrast: Math.sqrt(varSum / n),
            full_hl_ratio: hl / n,
            full_sh_ratio: sh / n,
        };
    }

    // ============================================================
    // 二、参数搜索
    // ============================================================
    function makeStatsCache() {
        let key = '', val = null;
        return function (pixels, params) {
            const k = params.bright + '|' + params.temp + '|' + params.tint + '|' +
                params.sat + '|' + params.contrast + '|' +
                params.highlight + '|' + params.shadow + '|' + pixels.length;
            if (k === key && val) return val;
            val = sampleSkinStats(applyParamsToSkinArray(pixels, params));
            key = k;
            return val;
        };
    }

    function meanHueSat(pixels) {
        const n = pixels.length / 3;
        if (n === 0) return null;
        let r = 0, g = 0, b = 0;
        for (let i = 0; i < n; i++) { r += pixels[i * 3]; g += pixels[i * 3 + 1]; b += pixels[i * 3 + 2]; }
        r /= n; g /= n; b /= n;
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
        let h = 0;
        if (d > 1e-9) {
            if (mx === r) h = ((g - b) / d) % 6;
            else if (mx === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h *= 60;
        }
        if (h > 180) h -= 360;
        if (h <= -180) h += 360;
        return { hue: h, sat: mx > 1e-6 ? d / mx : 0, lum: KR * r + KG * g + KB * b };
    }

    // Full bake pipeline on an RGB float array (same maths as generateLutData).
    function renderArray(pixels, params) {
        const out = applyParamsToSkinArray(pixels, params, true);
        const slope = shadowToeSlope(params);
        for (let i = 0; i < out.length; i += 3) {
            let t = applyShadowToe(pixels[i], pixels[i + 1], pixels[i + 2], out[i], out[i + 1], out[i + 2], slope);
            t = applyWhiteAnchor(pixels[i], pixels[i + 1], pixels[i + 2], t[0], t[1], t[2]);
            out[i] = Math.min(1, Math.max(0, t[0])); out[i + 1] = Math.min(1, Math.max(0, t[1])); out[i + 2] = Math.min(1, Math.max(0, t[2]));
        }
        return out;
    }

    function lumaArray(px) {
        const n = px.length / 3, y = new Float32Array(n);
        for (let i = 0; i < n; i++) y[i] = KR * px[i * 3] + KG * px[i * 3 + 1] + KB * px[i * 3 + 2];
        return y;
    }
    function quantile(arr, q) {
        const s = Float32Array.from(arr).sort();
        return s.length ? s[Math.min(s.length - 1, Math.floor(q * s.length))] : 0;
    }
    function meanStd(y, idx) {
        if (!idx.length) return [0, 0];
        let m = 0; for (const i of idx) m += y[i]; m /= idx.length;
        let v = 0; for (const i of idx) v += (y[i] - m) * (y[i] - m);
        return [m, Math.sqrt(v / idx.length)];
    }

    // Build 279: contrast / black point / white shape of a whole-frame sample (y = its luma).
    function globalShape(px, y, ref) {
        const n = y.length;
        let m = 0; for (let i = 0; i < n; i++) m += y[i]; m /= n;
        let v = 0; for (let i = 0; i < n; i++) v += (y[i] - m) * (y[i] - m);
        const sorted = Float32Array.from(y).sort();
        const q = (p) => sorted[Math.min(n - 1, Math.floor(p * n))];
        const o = { std: Math.sqrt(v / n), p5: q(0.05), p50: q(0.5), p95: q(0.95) };
        // index sets are fixed by the SOURCE frame so before/after compare the same pixels
        if (!ref) {
            const white = [], d3 = [];
            const cut = q(0.03);
            for (let i = 0; i < n; i++) {
                const r = px[i * 3], g = px[i * 3 + 1], b = px[i * 3 + 2];
                const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
                if (y[i] > 0.70 && (mx > 0 ? (mx - mn) / mx : 0) < 0.15) white.push(i);
                if (y[i] <= cut) d3.push(i);
            }
            o.white = white; o.d3 = d3;
        } else { o.white = ref.white; o.d3 = ref.d3; }
        o.whiteMean = meanStd(y, o.white)[0]; o.dark3 = meanStd(y, o.d3)[0];
        return o;
    }

    // Build 278: per-frame failure check of a param set. Returns the first failure or null.
    function safetyContext(globalSample, skinSample) {
        const SF = CONFIG.safety;
        const ctx = { g: null, s: null };
        if (globalSample && globalSample.length >= 3 * 64) {
            const y0 = lumaArray(globalSample);
            const dark = [], hl = [];
            let clip0 = 0;
            for (let i = 0; i < y0.length; i++) {
                if (y0[i] < SF.darkLuma) dark.push(i);
                if (y0[i] > SF.hlLuma) hl.push(i);
                if (y0[i] >= SF.clipLuma) clip0++;
            }
            const d = meanStd(y0, dark), h = meanStd(y0, hl);
            ctx.g = { px: globalSample, y0, n: y0.length, dark, hl, clip0: clip0 / y0.length, p1: quantile(y0, 0.01),
                darkMean: d[0], darkStd: d[1], hlMean: h[0], hlStd: h[1] };
            Object.assign(ctx.g, globalShape(globalSample, y0));
        }
        if (skinSample && skinSample.length >= 3 * 20) {
            const b = meanHueSat(skinSample);
            if (b && b.sat >= SF.minSkinSat && b.sat <= SF.maxSkinSat && b.lum >= SF.minSkinLum &&
                b.hue >= SF.hueRange[0] && b.hue <= SF.hueRange[1]) ctx.s = { px: skinSample, before: b };
        }
        return ctx;
    }
    function safetyFailure(ctx, params) {
        const SF = CONFIG.safety;
        if (ctx.s) {
            const a = meanHueSat(renderArray(ctx.s.px, params)), b = ctx.s.before;
            const floor = Math.min(SF.magentaHue, b.hue - SF.magentaExtraRot);
            if (a.hue < floor + SF.magentaMargin) return 'magenta';
            if (a.lum > SF.skinLumMax && a.lum > b.lum + 0.02) return 'skinwash';
            if (b.lum >= SF.highKeySkinLum && a.lum > b.lum + SF.highKeySkinRiseMax) return 'highkey';
            if (a.hue < SF.pinkHue && b.hue - a.hue > SF.pinkRotMax) return 'pink';
            if ((a.sat > SF.oversatAbs && a.sat > b.sat + 0.02) || (b.sat > 1e-6 && a.sat / b.sat > SF.oversatRatio)) return 'oversat';
        }
        if (ctx.g) {
            const g = ctx.g, y1 = lumaArray(renderArray(g.px, params));
            let clip1 = 0; for (let i = 0; i < y1.length; i++) if (y1[i] >= SF.clipLuma) clip1++;
            if (clip1 / g.n - g.clip0 > SF.clipAddMax) return 'hlblow';
            if (g.hl.length / g.n >= SF.hlMinFrac && g.hlStd > 0.01) {
                const h = meanStd(y1, g.hl);
                // flattened *upward* = blown; pulled-down compression is the intended highlight recovery
                if (h[1] / g.hlStd < SF.hlDetailMin && h[0] > g.hlMean - SF.hlMeanMargin) return 'hlblow';
            }
            if (g.dark.length / g.n >= SF.darkMinFrac) {
                const d = meanStd(y1, g.dark);
                if (g.darkMean > 0.004 && d[0] / g.darkMean < SF.darkMeanMin) return 'crush';
                if (g.darkStd > 0.004 && d[1] / g.darkStd < SF.darkDetailMin) return 'crush';
            }
            const p1 = quantile(y1, 0.01);
            if (g.p1 - p1 > SF.p1DropMax) return 'crush';
            if (p1 - g.p1 > SF.p1RiseMax) return 'lift';
            const o = globalShape(g.px, y1, g);
            if (o.p5 - g.p5 > SF.p5RiseMax || (g.d3.length && o.dark3 - g.dark3 > SF.dark3RiseMax)) return 'lift';
            if (g.white.length / g.n >= SF.whiteMinFrac && o.whiteMean < g.whiteMean - SF.whiteDropMax) return 'greywhite';
            if (g.p50 >= SF.highKeyP50 && o.p50 - g.p50 > SF.highKeyRiseMax) return 'highkey';
            if (g.std > 0.02 && (o.std / g.std < SF.hazeStdMin || (g.p95 - g.p5 > 0.02 && (o.p95 - o.p5) / (g.p95 - g.p5) < SF.hazeRangeMin))) return 'haze';
        }
        return null;
    }
    function safetyGuard(params, globalSample, skinSample) {
        const SF = CONFIG.safety;
        if (!SF.enabled) return { params, steps: 0, fixed: [] };
        const ctx = safetyContext(globalSample, skinSample);
        if (!ctx.g && !ctx.s) return { params, steps: 0, fixed: [] };
        let f = safetyFailure(ctx, params), steps = 0;
        const fixed = [];
        while (f && steps < SF.maxSteps) {
            steps++;
            if (fixed.indexOf(f) < 0) fixed.push(f);
            let moved = true;
            if (f === 'magenta') {
                if (params.tint > 0) params.tint -= 1;
                else if (params.temp < 0) params.temp += 1;
                else if (params.sat > SF.satFloor) params.sat -= 1;
                else moved = false;
            } else if (f === 'hlblow') {
                // Build 279: bounded highlight pull first (white anchor keeps neutral whites), then the lift
                if (params.highlight > SF.hlblowHighlightFloor) params.highlight -= 1;
                else if (params.bright > SF.brightFloor) params.bright -= 1;
                else if (params.contrast > 0) params.contrast -= 1;
                else moved = false;
            } else if (f === 'pink') {
                if (params.tint > 0) params.tint -= 1;
                else if (params.temp < 0) params.temp += 1;
                else moved = false;
            } else if (f === 'highkey') {
                if (params.bright > SF.brightFloor) params.bright -= 1;
                else if (params.shadow > 0) params.shadow -= 1;
                else if (params.highlight > 0) params.highlight -= 1;
                else moved = false;
            } else if (f === 'greywhite') {
                if (params.highlight < 0) params.highlight += 1;
                else if (params.contrast < 0) params.contrast += 1;
                else moved = false;
            } else if (f === 'haze') {
                if (params.shadow > 0) params.shadow -= 1;
                else if (params.highlight < 0) params.highlight += 1;
                else if (params.bright > SF.brightFloor) params.bright -= 1;
                else if (params.contrast < 4) params.contrast += 1;
                else moved = false;
            } else if (f === 'skinwash') {
                if (params.bright > SF.brightFloor) params.bright -= 1;
                else if (params.highlight > SF.highlightFloor) params.highlight -= 1;
                else moved = false;
            } else if (f === 'oversat') {
                if (params.sat > SF.satFloor) params.sat -= 1; else moved = false;
            } else if (f === 'crush') {
                if (params.contrast > 0) params.contrast -= 1;
                else if (params.shadow < SF.shadowCeil) params.shadow += 1;
                else moved = false;
            } else if (f === 'lift') {
                if (params.shadow > 0) params.shadow -= 1;
                else if (params.bright > SF.brightFloor) params.bright -= 1;
                else if (params.contrast < 4) params.contrast += 1;
                else moved = false;
            }
            if (!moved) break;
            f = safetyFailure(ctx, params);
        }
        if (steps > 0) console.log(`[LUT-算法-279安全] ${fixed.join('/')} ${steps} 步 → ${JSON.stringify(params)}`);
        return { params, steps, fixed, residual: f };
    }

    function activePreset() {
        return CONFIG.presets[CONFIG.preset] || CONFIG.presets.standard;
    }
    // Temporarily apply a preset's safety overrides (restored even if the guard throws).
    function withPresetSafety(preset, work) {
        const saved = {};
        for (const k of Object.keys(preset.safety)) { saved[k] = CONFIG.safety[k]; CONFIG.safety[k] = preset.safety[k]; }
        try { return work(); } finally { for (const k of Object.keys(saved)) CONFIG.safety[k] = saved[k]; }
    }
    function setPreset(name) {
        CONFIG.preset = Object.prototype.hasOwnProperty.call(CONFIG.presets, name) ? name : 'standard';
        return CONFIG.preset;
    }

    function predictParams(info, skinPixels, useExtreme, useHighMatch, globalSample) {
        // 输入结构适配（油猴无偏离帧逻辑）
        const features = Object.assign({}, info);
        features.skin_rgb = skinPixels;
        features.used_deviated = false;
        features.deviated_ratio = 0.0;
        features.deviated_direction = 'none';

        const template = useExtreme ? JY_TEMPLATE_EXTREME_DARK :
            useHighMatch ? JY_TEMPLATE_HIGH_MATCH : JY_TEMPLATE;

        const isCenterFallback = (info.regionName === '中央50%');

        // 模板与范围（中央50% + 高命中 仍用 HIGH_MATCH 范围；中央50% 单独用 CENTER 目标）
        let adjustRange;
        if (useExtreme) {
            adjustRange = JY_ADJUST_RANGE_EXTREME_DARK;
        } else if (useHighMatch) {
            // JY_ADJUST_RANGE_HIGH_MATCH_CENTER 已并入 JY_ADJUST_RANGE_HIGH_MATCH（脚本本身没有 CENTER 变体）
            adjustRange = JY_ADJUST_RANGE_HIGH_MATCH;
        } else {
            adjustRange = JY_ADJUST_RANGE;
        }
        let targets = useExtreme ? TARGETS_EXTREME_DARK :
            useHighMatch ? TARGETS_HIGH_MATCH : TARGETS;

        // 没有 CENTER 目标覆盖（predict_params 里没有 regionName 分支），
        // 但油猴的中央50%采样需要目标下移，这里保留油猴原版的 CENTER 目标适配（仅目标区间，不影响算法逻辑）
        const TARGETS_CENTER = {
            skin_rb:       [1.05, 1.35],
            skin_rg:       [1.15, 1.35],
            skin_lum:      [0.55, 0.75],
            skin_sat:      [0.08, 0.22],
            full_contrast: [0.10, 0.20],
            full_hl_ratio: [0.00, 0.20],
            full_sh_ratio: [0.00, 0.40],
        };
        if (isCenterFallback && !useHighMatch && !useExtreme) {
            targets = TARGETS_CENTER;
        }

        const origLum = info.skin_lum;
        const origSat = info.skin_sat;
        const skinRB = info.skin_rb;
        const highRB = info.high_rb !== undefined ? info.high_rb : 1.0;
        const highPixels = info.high_pixels !== undefined ? info.high_pixels : 0;

        const HH = CONFIG.highHlScene;
        const isHighHlScene = !useExtreme && (
            (info.full_hl_ratio || 0) > HH.hlRatioMin &&
            origLum > HH.lumMin &&
            highRB > HH.highRBMin
        );
        if (isHighHlScene) {
            console.log(
                `[LUT-算法-高光过量场景] full_hl_ratio=${(info.full_hl_ratio||0).toFixed(3)} ` +
                `> ${HH.hlRatioMin} 且 skin_lum=${origLum.toFixed(3)} > ${HH.lumMin} ` +
                `且 high_rb=${highRB.toFixed(3)} > ${HH.highRBMin} ` +
                `→ 启用激进高光/色温/对比度策略`
            );
        }

        let skinInherentlyYellow = false;
        let sceneColorCast = false;
        if (skinRB > CONFIG.skinRBHighThreshold &&
            highPixels >= CONFIG.highPixelMinCount) {
            if (highRB < CONFIG.highRBInherentMax) {
                skinInherentlyYellow = true;
                console.log(`[LUT-算法-肤色判定] 肤色 R/B=${skinRB.toFixed(3)} 高，但高光 R/B=${highRB.toFixed(3)} 正常（${highPixels} 像素）→ 判定为肤色本身偏黄，色温不猛降`);
            } else if (highRB > CONFIG.highRBColorCastMin) {
                sceneColorCast = true;
                console.log(`[LUT-算法-肤色判定] 肤色 R/B=${skinRB.toFixed(3)} 高，高光 R/B=${highRB.toFixed(3)} 也偏黄（${highPixels} 像素）→ 判定为画面偏色，色温正常纠正`);
            }
        }

        const lowHighPixels = (highPixels < CONFIG.highPixelLowThreshold);
        const darkSkin = (origLum < CONFIG.highPixelDarkSkinMax);
        const needForceBright = lowHighPixels && darkSkin && !useExtreme;

        const origShRatio = info.full_sh_ratio !== undefined ? info.full_sh_ratio : 0;
        const origHlRatio = info.full_hl_ratio !== undefined ? info.full_hl_ratio : 0;

        const satAndRBOk = (origSat > CONFIG.extraTempSatMin &&
                            skinRB > CONFIG.extraTempRBMin);
        const shadowOk = (origShRatio > CONFIG.extraTempShadowMin);
        const highlightOk = (origHlRatio <= CONFIG.extraTempHlMax);
        const needExtraTemp = satAndRBOk && shadowOk && highlightOk;

        if (needExtraTemp) {
            console.log(`[LUT-算法-额外降色温判定] skin_sat=${origSat.toFixed(3)} > ${CONFIG.extraTempSatMin} 且 skin_rb=${skinRB.toFixed(3)} > ${CONFIG.extraTempRBMin} 且 full_sh_ratio=${origShRatio.toFixed(4)} > ${CONFIG.extraTempShadowMin} 且 full_hl_ratio=${origHlRatio.toFixed(4)} <= ${CONFIG.extraTempHlMax} → 色温搜索后将额外降色温`);
        }

        // 无高光豁免
        const _orig_hl_ratio = origHlRatio;
        const _orig_lum_for_exempt = origLum !== undefined ? origLum : 0.5;
        const NO_HL_EXEMPT = (_orig_hl_ratio < 0.01 && _orig_lum_for_exempt >= 0.35);
        if (NO_HL_EXEMPT) {
            console.log(`[LUT-算法-无高光豁免] 高光占比=${_orig_hl_ratio.toFixed(4)} < 0.01 且 原片亮度=${_orig_lum_for_exempt.toFixed(3)} >= 0.35，亮度/高光搜索不压亮`);
        } else {
            if (_orig_hl_ratio >= 0.01) {
                console.log(`[LUT-算法-无高光豁免-失效] 高光占比=${_orig_hl_ratio.toFixed(4)} >= 0.01`);
            } else if (_orig_lum_for_exempt < 0.35) {
                console.log(`[LUT-算法-无高光豁免-失效] 原片亮度=${_orig_lum_for_exempt.toFixed(3)} < 0.35`);
            }
        }

        // 原片极亮标志
        const _orig_lum_is_bright = (origLum !== undefined && origLum !== null && origLum > 0.60);
        const BRIGHT_BRIGHT_SEARCH_LO = 3;
        if (_orig_lum_is_bright) {
            console.log(`[LUT-算法-亮度搜索-极亮限制] 原片亮度=${origLum.toFixed(3)} > 0.60，亮度搜索/复检起点限制为 +${BRIGHT_BRIGHT_SEARCH_LO}`);
        }

        const _conservative_scene = (
            skinRB !== undefined && skinRB !== null && skinRB > 2.0 &&
            origSat !== undefined && origSat !== null && origSat > 0.5 &&
            origLum !== undefined && origLum !== null && origLum < 0.35 &&
            !useExtreme
        );
        if (_conservative_scene) {
            console.log(`[LUT-算法-保守场景] R/B=${skinRB.toFixed(3)} > 2.0、饱和度=${origSat.toFixed(3)} > 0.5、原片亮度=${origLum.toFixed(3)} < 0.35，后续 bright 补偿将跳过`);
        }

        const coarse = subsample(skinPixels, CONFIG.coarseSampleSize);
        const statsCached = CONFIG.enableStatsCache ? makeStatsCache() : null;
        const statsOfCoarse = statsCached
            ? (p) => statsCached(coarse, p)
            : (p) => sampleSkinStats(applyParamsToSkinArray(coarse, p));

        let params = Object.assign({}, template);

        // ---- 色温 ----
        if (useHighMatch) {
            const rb = info.skin_rb;
            const [rbLo, rbHi] = targets.skin_rb;
            let tempBase;
            if (rb <= rbLo) tempBase = -3;
            else if (rb >= rbHi) tempBase = -8;
            else {
                const ratio = (rb - rbLo) / Math.max(rbHi - rbLo, 1e-6);
                tempBase = Math.round(-3 + ratio * (-8 - (-3)));
            }
            let bestTemp = tempBase, bestErr = Infinity;
            for (let d = -2; d <= 2; d++) {
                const p = Object.assign({}, params, { temp: tempBase + d });
                const detected = statsOfCoarse(p);
                let err = Math.pow(rangeError(detected.skin_rb, targets.skin_rb), 2);
                err += 0.001 * (d * d);
                if (err < bestErr) { bestErr = err; bestTemp = tempBase + d; }
            }
            params.temp = bestTemp;
        } else {
            const infoRb = info.skin_rb;
            const baseDetected = statsOfCoarse(params);
            const baseRb = baseDetected.skin_rb;
            let rbOffset = infoRb - baseRb;
            rbOffset = Math.max(-0.08, Math.min(0.08, rbOffset));
            console.log(`[LUT-算法-色温搜索] 基准修正: info_rb=${infoRb.toFixed(3)}, base_rb=${baseRb.toFixed(3)}, offset=${rbOffset >= 0 ? '+' : ''}${rbOffset.toFixed(3)}`);

            const [rbLo, rbHi] = targets.skin_rb;
            let rbTarget80;
            if (infoRb > 2.0) {
                rbTarget80 = rbHi;
                console.log(`[LUT-算法-色温搜索] 检测 R/B=${infoRb.toFixed(3)} > 2.0，R/B 目标 = 区间上限 ${rbTarget80.toFixed(3)}`);
            } else {
                rbTarget80 = rbLo + (rbHi - rbLo) * 0.6;
                console.log(`[LUT-算法-色温搜索] R/B 目标: 60% 位置 = ${rbTarget80.toFixed(3)}`);
            }

            if (skinInherentlyYellow) {
                const origTarget = rbTarget80;
                rbTarget80 = Math.max(rbTarget80, skinRB * CONFIG.inherentYellowRatio);
                console.log(`[LUT-算法-色温] 肤色本身偏黄，R/B 目标从 ${origTarget.toFixed(3)} 调整为 ${rbTarget80.toFixed(3)}`);
            }
            if (isHighHlScene) {
                const origTarget = rbTarget80;
                rbTarget80 = rbLo + (rbHi - rbLo) * 0.45;
                console.log(`[LUT-算法-色温] 高光过量场景，R/B 目标从 ${origTarget.toFixed(3)} 下调到 ${rbTarget80.toFixed(3)}`);
            }

            const rgW = isCenterFallback ? 1 : 5;
            const lumW = isCenterFallback ? 1 : 10;

            let bestTemp = params.temp, bestErr = Infinity;
            const tMin = isHighHlScene
                ? template.temp + adjustRange.temp[0] + HH.tempExtraMin
                : template.temp + adjustRange.temp[0];
            const tMax = template.temp + adjustRange.temp[1];
            for (let temp = tMin; temp <= tMax; temp += 1) {
                const p = Object.assign({}, params, { temp });
                const detected = statsOfCoarse(p);
                const correctedRb = detected.skin_rb + rbOffset;
                const rbErr = Math.max(0, Math.abs(correctedRb - rbTarget80) - 0.03);
                let err = 15 * rbErr * rbErr;
                err += rgW * Math.pow(rangeError(detected.skin_rg, targets.skin_rg), 2);
                err += lumW * Math.pow(rangeError(detected.skin_lum, targets.skin_lum), 2);
                err += 0.0005 * (temp - template.temp) * (temp - template.temp);
                if (err < bestErr) { bestErr = err; bestTemp = temp; }
            }
            params.temp = bestTemp;
        }

        // ---- 额外降色温 ----
        if (needExtraTemp && !useExtreme) {
            const [rbLo, rbHi] = targets.skin_rb;
            const rbTarget80 = rbLo + (rbHi - rbLo) * 0.8;
            const satTarget = (targets.skin_sat[0] + targets.skin_sat[1]) / 2;

            const tMin = isHighHlScene
                ? template.temp + adjustRange.temp[0] + HH.tempExtraMin
                : template.temp + adjustRange.temp[0];

            let temp = params.temp;
            let extra = 0;
            const maxExtra = CONFIG.extraTempMaxSteps;
            const step = CONFIG.extraTempStep;
            const satW = CONFIG.extraTempSatWeight;

            const prevDetected = statsOfCoarse(params);
            const prevRBErr = Math.abs(prevDetected.skin_rb - rbTarget80);
            const prevSatErr = Math.max(0, prevDetected.skin_sat - satTarget);
            let prevScore = prevRBErr + prevSatErr * satW;

            while (extra < maxExtra) {
                const nextTemp = temp - step;
                if (nextTemp < tMin) break;
                const p = Object.assign({}, params, { temp: nextTemp });
                const detected = statsOfCoarse(p);
                const rbErr = Math.abs(detected.skin_rb - rbTarget80);
                const satErr = Math.max(0, detected.skin_sat - satTarget);
                const score = rbErr + satErr * satW;
                if (score >= prevScore) break;
                temp = nextTemp;
                params.temp = temp;
                prevScore = score;
                extra++;
            }
            if (extra > 0) {
                console.log(`[LUT-算法-额外降色温] sat=${origSat.toFixed(3)} > ${CONFIG.extraTempSatMin} 且 R/B=${skinRB.toFixed(3)} > ${CONFIG.extraTempRBMin} → 色温继续降低 ${extra} 步（每步 ${step}），temp = ${params.temp}`);
            }
        }

        // ---- 亮度搜索 ----
        {
            const [lumLo, lumHi] = targets.skin_lum;
            let lumTarget = lumLo + (lumHi - lumLo) * 0.8;

            const _orig_rb_for_target = skinRB;
            const _orig_lum_for_target = origLum;
            const _orig_sat_for_target = origSat;

            if (_orig_rb_for_target !== undefined && _orig_rb_for_target !== null &&
                _orig_rb_for_target >= 2.0 &&
                _orig_sat_for_target !== undefined && _orig_sat_for_target !== null &&
                _orig_sat_for_target > 0.5 &&
                _orig_lum_for_target !== undefined && _orig_lum_for_target !== null &&
                _orig_lum_for_target < 0.35 && !useExtreme) {
                lumTarget = Math.max(_orig_lum_for_target + 0.04, 0.39);
                console.log(`[LUT-算法-亮度搜索-保守场景] R/B=${_orig_rb_for_target.toFixed(3)} >= 2.0、饱和度=${_orig_sat_for_target.toFixed(3)} > 0.5、原片亮度=${_orig_lum_for_target.toFixed(3)} < 0.35，亮度目标 = ${lumTarget.toFixed(3)}（原片+0.04，最低 0.39）`);
            } else if (_orig_lum_for_target !== undefined && _orig_lum_for_target !== null &&
                       _orig_lum_for_target > 0.54 && _orig_lum_for_target <= 0.60) {
                lumTarget = Math.min(_orig_lum_for_target + 0.02, 0.58);
                console.log(`[LUT-算法-亮度搜索-超亮动态] 原片亮度=${_orig_lum_for_target.toFixed(3)} ∈ (0.54, 0.60]，亮度目标 = ${lumTarget.toFixed(3)}（原片+0.02，上限 0.58）`);
            } else if (_orig_lum_for_target !== undefined && _orig_lum_for_target !== null &&
                       _orig_lum_for_target > 0.60) {
                lumTarget = 0.58;
                console.log(`[LUT-算法-亮度搜索-极亮压回] 原片亮度=${_orig_lum_for_target.toFixed(3)} > 0.60，亮度目标 = ${lumTarget.toFixed(3)}（压回 0.58）`);
            } else if (_orig_rb_for_target !== undefined && _orig_rb_for_target !== null &&
                       _orig_rb_for_target < 2.0 &&
                       _orig_lum_for_target !== undefined && _orig_lum_for_target !== null &&
                       _orig_lum_for_target >= 0.50 && _orig_lum_for_target <= 0.54) {
                lumTarget = _orig_lum_for_target + 0.05;
                console.log(`[LUT-算法-亮度搜索-高亮动态] R/B=${_orig_rb_for_target.toFixed(3)} < 2.0、原片亮度=${_orig_lum_for_target.toFixed(3)} ∈ [0.50, 0.54]，亮度目标 = ${lumTarget.toFixed(3)}（原片+0.05）`);
            } else if (_orig_rb_for_target !== undefined && _orig_rb_for_target !== null &&
                       _orig_rb_for_target < 2.0 &&
                       _orig_lum_for_target !== undefined && _orig_lum_for_target !== null &&
                       _orig_lum_for_target > 0.35 && _orig_lum_for_target < 0.50 &&
                       (info.full_hl_ratio || 0) > 0.005) {
                lumTarget = Math.min(_orig_lum_for_target + 0.09, 0.54);
                console.log(`[LUT-算法-亮度搜索-动态] R/B=${_orig_rb_for_target.toFixed(3)} < 2.0、原片亮度=${_orig_lum_for_target.toFixed(3)} ∈ (0.35, 0.50)、原片高光=${(info.full_hl_ratio||0).toFixed(3)} > 0.005，亮度目标 = ${lumTarget.toFixed(3)}（原片+0.09，上限 0.54）`);
            }
            console.log(`[LUT-算法-亮度搜索] 目标 = ${lumTarget.toFixed(3)}`);

            let bestBright = params.bright, bestErr = Infinity;
            const bMin = template.bright + adjustRange.bright[0];
            let bMax = template.bright + adjustRange.bright[1];

            if (_orig_lum_is_bright) {
                const lo = Math.max(bMin, template.bright + BRIGHT_BRIGHT_SEARCH_LO);
                params.bright = lo;
                console.log(`[LUT-算法-亮度搜索-极亮锁定] 原片 ${origLum.toFixed(3)} > 0.60，亮度直接锁定为 +${lo - template.bright}`);
            } else {
                if (isHighHlScene) {
                    bMax += HH.brightMaxExtra;
                    console.log(`[LUT-算法-亮度] 高光过量场景，bright 上限放宽到 ${bMax}`);
                }
                for (let bright = bMin; bright <= bMax; bright += 1) {
                    const p = Object.assign({}, params, { bright });
                    const detected = statsOfCoarse(p);
                    const curLum = detected.skin_lum;
                    let lumErr;
                    if (curLum < lumTarget) lumErr = Math.pow(lumTarget - curLum, 2);
                    else if (curLum > lumHi) lumErr = Math.pow(curLum - lumTarget, 2);
                    else lumErr = 0;
                    let err = lumErr;
                    const _temp_at_floor_search = (params.temp <= -40);
                    if (!_temp_at_floor_search) {
                        err += 2 * Math.pow(rangeError(detected.skin_rb, targets.skin_rb), 2);
                    }
                    if (err < bestErr) { bestErr = err; bestBright = bright; }
                }
                params.bright = bestBright;
            }

            // 亮度复检
            const postDetected = statsOfCoarse(params);
            const postLum = postDetected.skin_lum;
            console.log(`[LUT-算法-亮度复检] 色温搜索后亮度=${postLum.toFixed(3)}`);
            if (postLum < lumTarget * 0.9 || postLum > lumTarget * 1.1) {
                let bestBright2 = params.bright, bestErr2 = Infinity;
                const baseBright = params.bright;
                const lo2 = Math.max(adjustRange.bright[0], baseBright - 8 - template.bright);
                const hi2 = Math.min(adjustRange.bright[1], baseBright + 8 - template.bright);
                if (_orig_lum_is_bright) {
                    const lo2b = Math.max(lo2, BRIGHT_BRIGHT_SEARCH_LO);
                    if (params.bright !== lo2b) {
                        console.log(`[LUT-算法-亮度复检-极亮锁定] 原片 > 0.60，亮度从 ${params.bright >= 0 ? '+' : ''}${params.bright} 锁定为 +${lo2b}`);
                    }
                    params.bright = template.bright + lo2b;
                } else {
                    for (let delta = lo2; delta <= hi2; delta += 1) {
                        const bright = template.bright + delta;
                        const p = Object.assign({}, params, { bright });
                        const detected = statsOfCoarse(p);
                        let lumErr;
                        if (detected.skin_lum < lumTarget) lumErr = Math.pow(lumTarget - detected.skin_lum, 2);
                        else if (detected.skin_lum > lumHi) lumErr = Math.pow(detected.skin_lum - lumTarget, 2);
                        else lumErr = 0;
                        let err = lumErr;
                        const _temp_at_floor_recheck = (params.temp <= -40);
                        if (!_temp_at_floor_recheck) {
                            err += 2 * Math.pow(rangeError(detected.skin_rb, targets.skin_rb), 2);
                        }
                        if (err < bestErr2) { bestErr2 = err; bestBright2 = bright; }
                    }
                    if (bestBright2 !== params.bright) {
                        console.log(`[LUT-算法-亮度复检] 亮度从 ${params.bright >= 0 ? '+' : ''}${params.bright} 调整为 ${bestBright2 >= 0 ? '+' : ''}${bestBright2}`);
                    }
                    params.bright = bestBright2;
                }
            } else {
                console.log(`[LUT-算法-亮度复检] 亮度已在目标内，无需调整`);
            }
        }

        // ---- 色调 ----
        {
            const rgTarget = (targets.skin_rg[0] + targets.skin_rg[1]) / 2;
            let bestTint = params.tint, bestErr = Infinity;
            const tMin = template.tint + adjustRange.tint[0];
            const tMax = template.tint + adjustRange.tint[1];
            for (let tint = tMin; tint <= tMax; tint += 1) {
                const p = Object.assign({}, params, { tint });
                const detected = statsOfCoarse(p);
                let err = Math.pow(rangeError(detected.skin_rg,
                    [rgTarget * 0.95, rgTarget * 1.05]), 2);
                err += 0.001 * (tint - template.tint) * (tint - template.tint);
                if (err < bestErr) { bestErr = err; bestTint = tint; }
            }
            params.tint = bestTint;

            // 人脸框色调逻辑（保留油猴原版的人脸框补血色判定）
            const isFaceBox = (info.regionName === '人脸框');
            if (isFaceBox) {
                const origRg = info.skin_rg !== undefined ? info.skin_rg : 1.0;
                const origRb = info.skin_rb !== undefined ? info.skin_rb : 1.0;
                const rgRbRatio = origRg / Math.max(origRb, 1e-6);
                const RED_RATIO = 0.88;
                const TINT_NEG_FLOOR = -6;
                console.log(`[LUT-算法-色调][人脸框] skin_rg=${origRg.toFixed(3)}，skin_rb=${origRb.toFixed(3)}，rg/rb=${rgRbRatio.toFixed(3)}`);
                if (rgRbRatio > RED_RATIO) {
                    console.log(`[LUT-算法-色调][人脸框] 太红（rg/rb=${rgRbRatio.toFixed(3)} > ${RED_RATIO}）→ 不补血色，保留搜索值 tint=${params.tint}`);
                    if (params.tint < TINT_NEG_FLOOR) {
                        console.log(`[LUT-算法-色调][人脸框] tint=${params.tint} < ${TINT_NEG_FLOOR} → 钳制到 ${TINT_NEG_FLOOR}`);
                        params.tint = TINT_NEG_FLOOR;
                    }
                } else {
                    if (params.tint < 6) {
                        console.log(`[LUT-算法-色调][人脸框] 非太红（rg/rb=${rgRbRatio.toFixed(3)} ≤ ${RED_RATIO}），tint=${params.tint} < 6 → 强制为 6（补血色）`);
                        params.tint = 6;
                    } else {
                        console.log(`[LUT-算法-色调][人脸框] 非太红（rg/rb=${rgRbRatio.toFixed(3)}），tint=${params.tint} ≥ 6，保持原样`);
                    }
                }
            } else {
                if (params.tint < 6) {
                    console.log(`[LUT-算法-色调][${info.regionName}] tint=${params.tint} < 6 → 强制为 6（补血色）`);
                    params.tint = 6;
                }
            }
        }

        // ---- 饱和度 ----
        {
            let satTarget;
            if (isHighHlScene) {
                satTarget = targets.skin_sat[1] * HH.satTargetFactor;
                console.log(`[LUT-算法-饱和度] 高光过量场景，饱和度目标抬到 ${satTarget.toFixed(3)}`);
            } else if (origSat !== undefined && origSat !== null && origSat > targets.skin_sat[1]) {
                satTarget = targets.skin_sat[1] * 0.95;
            } else {
                satTarget = (targets.skin_sat[0] + targets.skin_sat[1]) / 2;
            }

            let sMin, sMax;
            let satDeviationWeight = 0.001;
            const severe = !isCenterFallback && (origSat !== undefined && origSat !== null && origSat > CONFIG.severeSatThreshold);
            if (severe) {
                sMin = CONFIG.severeSatMin;
                sMax = 0;
                satDeviationWeight = 0.00005;
                console.log(`[LUT-算法-饱和度] 原片饱和度=${origSat.toFixed(3)} > ${CONFIG.severeSatThreshold}，扩大搜索范围到 [${sMin}, ${sMax}]，偏离惩罚权重=${satDeviationWeight}`);
            } else {
                sMin = template.sat + adjustRange.sat[0];
                sMax = template.sat + adjustRange.sat[1];
                if (isHighHlScene) sMax += HH.satMaxExtra;
            }

            let bestSat = params.sat, bestErr = Infinity;
            for (let sat = sMin; sat <= sMax; sat += 1) {
                const p = Object.assign({}, params, { sat });
                const detected = statsOfCoarse(p);
                let err = Math.pow(rangeError(detected.skin_sat,
                    [satTarget * 0.9, satTarget * 1.1]), 2);
                err += satDeviationWeight * (sat - template.sat) * (sat - template.sat);
                if (err < bestErr) { bestErr = err; bestSat = sat; }
            }
            params.sat = bestSat;
            console.log(`[LUT-算法-饱和度] 搜索完成，sat=${bestSat}，检测值=${statsOfCoarse(params).skin_sat.toFixed(3)}，目标区间=[${(satTarget * 0.9).toFixed(3)}, ${(satTarget * 1.1).toFixed(3)}]`);
        }

        // ---- 对比度 ----
        {
            let bestContrast = params.contrast, bestErr = Infinity;
            const cMin = template.contrast + adjustRange.contrast[0];
            let cMax = template.contrast + adjustRange.contrast[1];
            if (isHighHlScene) cMax += 2;

            const contrastTarget = isHighHlScene
                ? [(targets.full_contrast[0] + targets.full_contrast[1]) / 2 + HH.contrastTargetShift,
                   targets.full_contrast[1] + HH.contrastTargetShift]
                : targets.full_contrast;
            const contrastDevW = isHighHlScene ? HH.contrastDevWeight : 0.001;

            for (let contrast = cMin; contrast <= cMax; contrast += 1) {
                const p = Object.assign({}, params, { contrast });
                const detected = statsOfCoarse(p);
                let err = Math.pow(rangeError(detected.full_contrast, contrastTarget), 2);
                err += contrastDevW * (contrast - template.contrast) * (contrast - template.contrast);
                if (err < bestErr) { bestErr = err; bestContrast = contrast; }
            }
            params.contrast = bestContrast;
        }

        // ---- 高光补偿 ----
        let hlCompensation = 0;
        const hlCompMin = isHighHlScene ? HH.hlCompMin : -10;
        if (!useExtreme) {
            const origHl = info.full_hl_ratio || 0;
            const origLumForHl = info.skin_lum || 0.5;
            const [, hlHiT] = getDynamicHlTarget(origLumForHl);
            if (origHl > hlHiT) {
                const brightBoost = Math.max(0, params.bright - 5);
                const shadowBoost = Math.max(0, params.shadow - 2);
                hlCompensation = Math.round(-(brightBoost * 1.0 + shadowBoost * 0.5));
                hlCompensation = Math.max(hlCompensation, hlCompMin);
            }
        }
        if (!useExtreme && params.bright > CONFIG.autoHlCompBrightThreshold) {
            const origHlForComp = info.full_hl_ratio || 0;
            if (origHlForComp < CONFIG.autoHlCompMinOrigHl) {
                console.log(`[LUT-算法-自动高光压缩] 原片高光=${origHlForComp.toFixed(4)} < ${CONFIG.autoHlCompMinOrigHl}，原片本身高光极少，跳过自动高光压缩`);
            } else {
                const extra = Math.round((params.bright - CONFIG.autoHlCompBrightThreshold) * CONFIG.autoHlCompStrength);
                if (extra > 0) {
                    hlCompensation -= extra;
                    hlCompensation = Math.max(hlCompensation, hlCompMin);
                    console.log(`[LUT-算法-自动高光压缩] bright=${params.bright} > ${CONFIG.autoHlCompBrightThreshold}，highlight 额外压 ${extra} 档，hlCompensation=${hlCompensation}`);
                }
            }
        }

        // ---- 高光搜索 ----
        {
            const baseDetected = statsOfCoarse(params);
            const currentLum = baseDetected.skin_lum;
            let [hlLo, hlHi] = getDynamicHlTarget(currentLum);
            if (isHighHlScene) {
                hlHi = Math.min(hlHi, HH.hlHiCap);
                console.log(`[LUT-算法-高光搜索] 高光过量场景，hlHi 收紧到 ${hlHi.toFixed(3)}`);
            }
            console.log(`[LUT-算法-高光搜索] 当前皮肤亮度=${currentLum.toFixed(3)}，动态高光目标=[${hlLo.toFixed(3)}, ${hlHi.toFixed(3)}]`);

            const hlBase = template.highlight + hlCompensation;
            let bestHl = params.highlight, bestErr = Infinity;
            const hMin = isHighHlScene ? -16 : adjustRange.highlight[0];
            const hMax = adjustRange.highlight[1];
            const hlHardMin = isHighHlScene
                ? HH.highlightHardMin
                : (isCenterFallback && useHighMatch ? -5 : -10);

            for (let delta = hMin; delta <= hMax; delta += 1) {
                const hl = hlBase + delta;
                const p = Object.assign({}, params, { highlight: hl });
                const detected = statsOfCoarse(p);
                let err;
                if (NO_HL_EXEMPT) {
                    err = 0.0;
                } else {
                    err = Math.pow(rangeError(detected.full_hl_ratio, [hlLo, hlHi]), 2);
                }
                err += 10 * Math.pow(rangeError(detected.skin_rb, targets.skin_rb), 2);
                if (err < bestErr) { bestErr = err; bestHl = hl; }
            }
            params.highlight = Math.max(bestHl, hlHardMin);
        }

        // ---- 阴影 ----
        {
            const DARK_LUM_THRESHOLD = 0.20;
            const DARK_LUM_TARGET = 0.30;
            const pBase = Object.assign({}, params, { shadow: 0 });
            const baseTransformed = applyParamsToSkinArray(coarse, pBase);
            const nPix = baseTransformed.length / 3;
            const darkMask = new Uint8Array(nPix);
            let nDark = 0;
            for (let i = 0; i < nPix; i++) {
                const lum = KR * baseTransformed[i * 3] +
                    KG * baseTransformed[i * 3 + 1] +
                    KB * baseTransformed[i * 3 + 2];
                if (lum < DARK_LUM_THRESHOLD) { darkMask[i] = 1; nDark++; }
            }
            if (nDark > 0) {
                let bestSh = params.shadow, bestErr = Infinity;
                const sMin = template.shadow + adjustRange.shadow[0];
                const sMax = isHighHlScene
                    ? template.shadow + Math.round(adjustRange.shadow[1] * HH.shadowMaxFactor)
                    : template.shadow + adjustRange.shadow[1];
                for (let sh = sMin; sh <= sMax; sh += 1) {
                    const p = Object.assign({}, params, { shadow: sh });
                    const transformed = applyParamsToSkinArray(coarse, p);
                    const darkLums = [];
                    for (let i = 0; i < nPix; i++) {
                        if (darkMask[i]) {
                            darkLums.push(
                                KR * transformed[i * 3] +
                                KG * transformed[i * 3 + 1] +
                                KB * transformed[i * 3 + 2]
                            );
                        }
                    }
                    darkLums.sort((a, b) => a - b);
                    const medDark = darkLums[Math.floor(darkLums.length / 2)];
                    let err = Math.pow(medDark - DARK_LUM_TARGET, 2);
                    const detected = sampleSkinStats(transformed);
                    err += 1 * Math.pow(rangeError(detected.skin_rb, targets.skin_rb), 2);
                    if (err < bestErr) { bestErr = err; bestSh = sh; }
                }
                params.shadow = bestSh;
            }
        }

        // ---- 最终亮度复检 ----
        {
            const finalDetected = statsOfCoarse(params);
            const finalLum = finalDetected.skin_lum;
            const [lumLo, lumHi] = targets.skin_lum;
            let lumTarget = lumLo + (lumHi - lumLo) * 0.8;

            const rbHi = targets.skin_rb[1];
            const rbTrigger = rbHi * 1.2;
            let lumTargetHigh;
            if (info.skin_rb > rbTrigger) {
                lumTargetHigh = lumLo + (lumHi - lumLo) * 0.9;
            } else {
                lumTargetHigh = lumTarget;
            }

            const LUM_HARD_FLOOR = useExtreme ? 0.0 : lumLo;
            console.log(`[LUT-算法-最终亮度复检] 原片亮度=${origLum !== undefined ? origLum.toFixed(3) : 0}，调整后亮度=${finalLum.toFixed(3)}，目标区间=[${lumLo.toFixed(3)}, ${lumHi.toFixed(3)}]`);
            console.log(`[LUT-算法-最终亮度复检] 亮度硬下限 = ${LUM_HARD_FLOOR}`);

            const origLumInRange = (origLum !== undefined && origLum !== null && lumLo <= origLum && origLum <= lumHi);
            const origBelowFloor = (origLum !== undefined && origLum !== null && origLum < LUM_HARD_FLOOR);

            let needRecheck = false;
            let recheckReason = '';
            if (origLum !== undefined && origLum !== null &&
                lumHi < origLum && origLum <= 0.60 &&
                finalLum < origLum + 0.02 - 0.005) {
                needRecheck = true;
                recheckReason = `原片亮度 ${origLum.toFixed(3)} ∈ (0.54, 0.60]，目标 ${(origLum + 0.02).toFixed(3)}，当前 ${finalLum.toFixed(3)} 未达标`;
            } else if (origLum !== undefined && origLum !== null &&
                       origLum > 0.60 && finalLum < 0.60 - 0.005) {
                needRecheck = true;
                recheckReason = `原片亮度 ${origLum.toFixed(3)} > 0.60，目标 0.600，当前 ${finalLum.toFixed(3)} 未达标`;
            } else if (origLumInRange && finalLum < origLum - 0.005) {
                needRecheck = true;
                recheckReason = `原片亮度 ${origLum.toFixed(3)} 在区间内，调整后被压到 ${finalLum.toFixed(3)}`;
            } else if (origBelowFloor && finalLum < LUM_HARD_FLOOR) {
                needRecheck = true;
                recheckReason = `原片亮度 ${origLum.toFixed(3)} 低于硬下限 ${LUM_HARD_FLOOR}，调整后仍为 ${finalLum.toFixed(3)}`;
            } else if (finalLum > lumHi * 1.05 &&
                       !(origLum !== undefined && origLum !== null &&
                         skinRB !== undefined && skinRB !== null && skinRB < 2.0 &&
                         origLum >= 0.50 && origLum <= 0.60)) {
                needRecheck = true;
                recheckReason = `调整后亮度 ${finalLum.toFixed(3)} 超出上限 ${lumHi.toFixed(3)}`;
            }

            if (needRecheck) {
                console.log(`[LUT-算法-最终亮度复检] 触发复检：${recheckReason}`);

                let recheckTarget;
                if (origLum !== undefined && origLum !== null && lumHi < origLum && origLum <= 0.60) {
                    recheckTarget = origLum + 0.02;
                } else if (origLum !== undefined && origLum !== null && origLum > 0.60) {
                    recheckTarget = 0.60;
                } else if (origLumInRange) {
                    recheckTarget = origBelowFloor ? Math.max(origLum, LUM_HARD_FLOOR) : origLum;
                } else if (origBelowFloor) {
                    recheckTarget = LUM_HARD_FLOOR;
                } else {
                    recheckTarget = finalLum;
                }

                if (!(origLum !== undefined && origLum !== null && origLum > lumHi)) {
                    if (recheckTarget < finalLum) {
                        console.log(`[LUT-算法-最终亮度复检] 目标 ${recheckTarget.toFixed(3)} < 当前亮度 ${finalLum.toFixed(3)}，提升到当前亮度`);
                        recheckTarget = finalLum;
                    }
                }
                console.log(`[LUT-算法-最终亮度复检] 复检目标亮度 = ${recheckTarget.toFixed(3)}`);

                let bestBright3 = params.bright, bestErr3 = Infinity;
                const baseBright3 = params.bright;
                const lo3 = Math.max(adjustRange.bright[0], baseBright3 - 6 - template.bright);
                const hi3 = Math.min(adjustRange.bright[1], baseBright3 + 15 - template.bright);
                if (_orig_lum_is_bright) {
                    const lo3b = Math.max(lo3, BRIGHT_BRIGHT_SEARCH_LO);
                    if (params.bright !== lo3b) {
                        console.log(`[LUT-算法-最终复检-极亮锁定] 原片 > 0.60，亮度从 ${params.bright} 锁定为 +${lo3b}`);
                    }
                    params.bright = template.bright + lo3b;
                } else {
                    for (let delta = lo3; delta <= hi3; delta += 1) {
                        const bright = template.bright + delta;
                        const p = Object.assign({}, params, { bright });
                        const detected = statsOfCoarse(p);
                        let lumErr;
                        if (detected.skin_lum < recheckTarget) lumErr = Math.pow(recheckTarget - detected.skin_lum, 2);
                        else if (recheckTarget <= lumHi && detected.skin_lum > lumHi) lumErr = Math.pow(detected.skin_lum - lumHi, 2);
                        else lumErr = 0;
                        let err = lumErr;
                        const _temp_at_floor_final = (params.temp <= -40);
                        if (!_temp_at_floor_final) {
                            err += 2 * Math.pow(rangeError(detected.skin_rb, targets.skin_rb), 2);
                        }
                        err += 0.0001 * Math.abs(detected.skin_lum - recheckTarget);
                        if (err < bestErr3) { bestErr3 = err; bestBright3 = bright; }
                    }
                    if (bestBright3 !== params.bright) {
                        console.log(`[LUT-算法-最终亮度复检] 亮度从 ${params.bright} 调整为 ${bestBright3}`);
                    }
                    params.bright = bestBright3;
                }
            } else {
                console.log(`[LUT-算法-最终亮度复检] 无需调整`);
            }
        }

        // ---- 标准模板亮度下限 ----
        if (!useExtreme && !useHighMatch) {
            const TEMP_FLOOR_THRESHOLD = -18;
            const BRIGHT_FLOOR_STD = 7;
            const _orig_lum_std = origLum;
            const _orig_hl_std = info.full_hl_ratio || 0;
            const _cond_temp = (params.temp > TEMP_FLOOR_THRESHOLD);
            const _cond_lum = (_orig_lum_std !== undefined && _orig_lum_std !== null &&
                targets.skin_lum[0] <= _orig_lum_std && _orig_lum_std <= targets.skin_lum[1]);
            const _cond_hl = (_orig_hl_std < 0.10);
            if (_cond_temp && _cond_lum && _cond_hl) {
                if (params.bright < BRIGHT_FLOOR_STD) {
                    console.log(`[LUT-算法-标准模板-亮度下限] bright ${params.bright} → ${BRIGHT_FLOOR_STD}`);
                    params.bright = BRIGHT_FLOOR_STD;
                }
            }
        }

        // ---- 力度协调 ----
        const _cons_rb = info.skin_rb;
        const _cons_sat = info.skin_sat;
        const _cons_lum = info.skin_lum;
        const _cons_scene = (
            _cons_rb !== undefined && _cons_rb !== null && _cons_rb > 2.0 &&
            _cons_sat !== undefined && _cons_sat !== null && _cons_sat > 0.5 &&
            _cons_lum !== undefined && _cons_lum !== null && _cons_lum < 0.35
        );
        params = _balanceParamStrength(params, template, adjustRange, useExtreme, useHighMatch, _cons_scene);

        // ---- 高亮撤销补血色 ----
        const BRIGHT_NO_TINT_THRESHOLD = 35;
        if (params.bright > BRIGHT_NO_TINT_THRESHOLD && params.tint > 0) {
            console.log(`[LUT-算法-色调] bright=${params.bright} > ${BRIGHT_NO_TINT_THRESHOLD}，撤销补血色，tint ${params.tint} → 0`);
            params.tint = 0;
        } else if (params.bright > BRIGHT_NO_TINT_THRESHOLD) {
            console.log(`[LUT-算法-色调] bright=${params.bright} > ${BRIGHT_NO_TINT_THRESHOLD}，但 tint=${params.tint} ≤ 0，保持原样`);
        }

        // ---- 灰块防护 ----
        {
            const GRAY_BLOCK_BRIGHT_THRESHOLD = 20;
            if (params.bright >= GRAY_BLOCK_BRIGHT_THRESHOLD) {
                if (params.contrast < 0) {
                    console.log(`[LUT-算法-灰块防护] bright=${params.bright} >= ${GRAY_BLOCK_BRIGHT_THRESHOLD}，contrast ${params.contrast} → 0`);
                    params.contrast = 0;
                }
                if (params.sat < 0) {
                    console.log(`[LUT-算法-灰块防护] bright=${params.bright} >= ${GRAY_BLOCK_BRIGHT_THRESHOLD}，sat ${params.sat} → 0`);
                    params.sat = 0;
                }
            }
        }

        // ---- 高光钳制 ----
        {
            const _hl_for_clamp = info.full_hl_ratio || 0;
            const _rb_for_clamp = info.skin_rb || 1.0;
            if (_hl_for_clamp > 0.18 && _rb_for_clamp > 1.8) {
                const brightRaise = params.bright - template.bright;
                if (brightRaise > 0) {
                    const reduced = Math.round(brightRaise * 0.7);
                    console.log(`[LUT-算法-高光钳制] 亮度提高量 ${brightRaise} → ${reduced}（×0.7）`);
                    params.bright = template.bright + reduced;
                }
                if (params.highlight > 0) {
                    console.log(`[LUT-算法-高光钳制] highlight=${params.highlight} > 0 → 强制为 -1`);
                    params.highlight = -1;
                }
            }
        }

        // ---- 过曝联动 ----
        let _contrast_boosted = false;
        if (!useExtreme) {
            const _orig_lum_for_link = info.skin_lum;
            const _orig_lum_in_range_link = (
                _orig_lum_for_link !== undefined && _orig_lum_for_link !== null &&
                targets.skin_lum[0] <= _orig_lum_for_link && _orig_lum_for_link <= targets.skin_lum[1]
            );
            let brightTrigger = false, hlTrigger = false;
            if (_orig_lum_in_range_link) {
                console.log(`[LUT-算法-联动] 原片亮度 ${_orig_lum_for_link.toFixed(3)} 已在目标区间内，跳过`);
            } else {
                brightTrigger = (params.bright >= 15);
                hlTrigger = (params.bright < 15 && params.highlight < -10);
            }

            if (brightTrigger || hlTrigger) {
                const reason = brightTrigger
                    ? `bright=${params.bright} >= 15`
                    : `bright=${params.bright} < 15 且 highlight=${params.highlight} < -10`;
                console.log(`[LUT-算法-联动触发] 原因：${reason}`);

                if (brightTrigger) {
                    if (_contrast_boosted) {
                        console.log(`[LUT-算法-联动] 已做对比度回压，跳过 temp 强制 -8`);
                    } else if (params.temp > -15) {
                        console.log(`[LUT-算法-联动] temp=${params.temp} > -15 → 强制为 -8`);
                        params.temp = -8;
                    }
                } else {
                    const HL_TRIGGER_TEMP_FLOOR = -20;
                    if (_conservative_scene) {
                        console.log(`[LUT-算法-过曝回暖] 保守场景，跳过`);
                    } else if (_contrast_boosted) {
                        console.log(`[LUT-算法-过曝回暖] 已做对比度回压，跳过`);
                    } else if (params.temp < HL_TRIGGER_TEMP_FLOOR) {
                        console.log(`[LUT-算法-过曝回暖] temp=${params.temp} → ${HL_TRIGGER_TEMP_FLOOR}`);
                        params.temp = HL_TRIGGER_TEMP_FLOOR;
                    }
                    if (!_conservative_scene) {
                        const HL_TRIGGER_HL_FLOOR = -5;
                        if (params.highlight < HL_TRIGGER_HL_FLOOR) {
                            console.log(`[LUT-算法-过曝高光钳制] highlight=${params.highlight} → ${HL_TRIGGER_HL_FLOOR}`);
                            params.highlight = HL_TRIGGER_HL_FLOOR;
                        }
                    }
                }

                if (params.bright >= 20) {
                    console.log(`[LUT-算法-联动] bright=${params.bright} >= 20，跳过 contrast/sat 联动`);
                } else if (brightTrigger) {
                    if (params.contrast > -1) {
                        console.log(`[LUT-算法-联动] contrast ${params.contrast} → -1`);
                        params.contrast = -1;
                    }
                    if (params.sat > -1) {
                        console.log(`[LUT-算法-联动] sat ${params.sat} → -1`);
                        params.sat = -1;
                    }
                } else {
                    if (params.contrast > -1) {
                        console.log(`[LUT-算法-过曝联动] contrast ${params.contrast} → -1`);
                        params.contrast = -1;
                    }
                    const SAT_FLOOR_HL = 1;
                    if (params.sat < SAT_FLOOR_HL) {
                        console.log(`[LUT-算法-过曝联动] sat ${params.sat} → ${SAT_FLOOR_HL}`);
                        params.sat = SAT_FLOOR_HL;
                    }
                }
            }
        }

        // ---- 白雾补偿 ----
        if (!useExtreme && params.bright > 0) {
            const CONTRAST_PER_BRIGHT = 0.5;
            const CONTRAST_MAX = 6;
            _contrast_boosted = false;
            const needed_contrast = Math.min(Math.round(params.bright * CONTRAST_PER_BRIGHT), CONTRAST_MAX);
            if (params.contrast < needed_contrast) {
                console.log(`[LUT-算法-白雾补偿] bright=${params.bright}，contrast ${params.contrast} → ${needed_contrast}`);
                params.contrast = needed_contrast;
                _contrast_boosted = true;
            }
            let sat_floor = -Math.round(params.contrast / 5.0);
            sat_floor = Math.max(sat_floor, -2);
            if (sat_floor < 0 && params.sat > sat_floor) {
                console.log(`[LUT-算法-白雾补偿] contrast=${params.contrast}，sat ${params.sat} → ${sat_floor}`);
                params.sat = sat_floor;
            }
        } else {
            _contrast_boosted = false;
        }

        // ---- 对比度色温回压 ----
        if (!useExtreme && !useHighMatch && params.contrast > 0) {
            const c = params.contrast;
            let temp_drop = 0;
            if (c >= 1 && c <= 3) temp_drop = 3;
            else if (c >= 4 && c <= 6) temp_drop = 6;
            if (temp_drop > 0) {
                let new_temp = params.temp - temp_drop;
                const temp_floor = template.temp + adjustRange.temp[0];
                new_temp = Math.max(new_temp, temp_floor);
                if (new_temp !== params.temp) {
                    console.log(`[LUT-算法-对比度色温回压] contrast=${c}，temp ${params.temp} → ${new_temp}`);
                    params.temp = new_temp;
                }
            }
        }

        // ---- 对比度色调回压 ----
        if (!useExtreme && !useHighMatch && params.contrast > 0) {
            if (params.tint > 0) {
                const c = params.contrast;
                let tint_drop = Math.round(c / 2);
                if (tint_drop > params.tint) tint_drop = params.tint;
                if (tint_drop > 0) {
                    const new_tint = params.tint - tint_drop;
                    console.log(`[LUT-算法-对比度色调回压] contrast=${c}，tint ${params.tint} → ${new_tint}`);
                    params.tint = new_tint;
                }
            }
        }

        // ---- 缺亮补亮 ----
        const HL_RATIO_LOW_THRESHOLD = 0.02;
        const HIGH_PIXEL_DARK_SKIN_MAX = 0.52;
        const HIGH_PIXEL_FORCE_BRIGHT = 20;
        const low_hl_ratio = ((info.full_hl_ratio || 0) < HL_RATIO_LOW_THRESHOLD);
        const dark_skin = ((info.skin_lum || 0.5) < HIGH_PIXEL_DARK_SKIN_MAX);
        const temp_at_floor = (params.temp <= -40);

        const _orig_lum_for_boost = info.skin_lum;
        const _temp_in_range = (params.temp > -40 && params.temp <= -30);
        const _orig_lum_bright = (_orig_lum_for_boost !== undefined && _orig_lum_for_boost !== null && _orig_lum_for_boost > 0.35);
        const _weaken_boost = _temp_in_range && _orig_lum_bright;

        if (low_hl_ratio && dark_skin && !useExtreme && !temp_at_floor && !NO_HL_EXEMPT && !_conservative_scene) {
            const bMax = template.bright + adjustRange.bright[1];
            const ratio = Math.max(0, Math.min(1, (info.full_hl_ratio || 0) / HL_RATIO_LOW_THRESHOLD));
            let dynamic_target = Math.round(HIGH_PIXEL_FORCE_BRIGHT * (1 - ratio) + params.bright * ratio);
            if (_weaken_boost) {
                const original_gain = dynamic_target - params.bright;
                const weakened_gain = Math.round(original_gain * 0.4);
                dynamic_target = params.bright + weakened_gain;
                console.log(`[LUT-算法-缺亮补亮] 补偿减弱 60% → ${dynamic_target}`);
            }
            const target_bright = Math.min(dynamic_target, bMax);
            if (params.bright < target_bright) {
                console.log(`[LUT-算法-缺亮补亮] bright ${params.bright} → ${target_bright}`);
                params.bright = target_bright;
            }
        }

        // ---- 缺亮补亮后高光复检 ----
        if (!useExtreme && params.bright > template.bright && !NO_HL_EXEMPT) {
            const _post_hl_detected = statsOfCoarse(params);
            const _post_hl_lum = _post_hl_detected.skin_lum;
            const [_post_hl_lo, _post_hl_hi] = getDynamicHlTarget(_post_hl_lum);
            console.log(`[LUT-算法-缺亮补亮后-高光复检] bright=${params.bright}，当前 hl=${_post_hl_detected.full_hl_ratio.toFixed(3)}`);
            let best_hl2 = params.highlight, best_err2 = Infinity;
            const lo2 = adjustRange.highlight[0];
            const hi2 = adjustRange.highlight[1];
            const hl_base2 = template.highlight + hlCompensation;
            for (let delta = lo2; delta <= hi2; delta += 1) {
                const hl = hl_base2 + delta;
                const p = Object.assign({}, params, { highlight: hl });
                const detected = statsOfCoarse(p);
                const err = 100 * Math.pow(rangeError(detected.full_hl_ratio, [_post_hl_lo, _post_hl_hi]), 2);
                if (err < best_err2) { best_err2 = err; best_hl2 = hl; }
            }
            if (best_hl2 !== params.highlight) {
                console.log(`[LUT-算法-缺亮补亮后-高光复检] highlight 从 ${params.highlight} 调整为 ${best_hl2}`);
            }
            params.highlight = best_hl2;
        }

        // ---- 高光最终钳制 ----
        if (!useExtreme) {
            const HL_FINAL_MIN = -7;
            if (params.highlight < HL_FINAL_MIN) {
                console.log(`[LUT-算法-高光最终钳制] highlight ${params.highlight} < ${HL_FINAL_MIN} → ${HL_FINAL_MIN}`);
                params.highlight = HL_FINAL_MIN;
            }
        }

        // ---- 标准模板-高光放行提亮 ----
        if (!useExtreme && !useHighMatch) {
            if (skinPixels !== null && skinPixels.length > 0) {
                const BRIGHT_CAP = 18;
                const HL_START = 0.20;
                const HL_STOP = 0.22;
                const _hl_detected = statsOfCoarse(params);
                const _hl_now = _hl_detected.full_hl_ratio;
                if (params.bright < BRIGHT_CAP && _hl_now < HL_START) {
                    console.log(`[LUT-算法-标准-高光放行提亮] bright=${params.bright} < ${BRIGHT_CAP}，当前高光=${_hl_now.toFixed(3)} < ${HL_START}，开始逐档加亮`);
                    const bright_lo = params.bright;
                    const bright_hi = Math.min(BRIGHT_CAP, template.bright + adjustRange.bright[1]);
                    let chosen_bright = params.bright;
                    for (let bright = bright_lo; bright <= bright_hi; bright++) {
                        const p = Object.assign({}, params, { bright });
                        const det = statsOfCoarse(p);
                        if (det.full_hl_ratio >= HL_STOP) {
                            chosen_bright = Math.max(bright_lo, bright - 1);
                            console.log(`[LUT-算法-标准-高光放行提亮] bright=${bright} 时高光=${det.full_hl_ratio.toFixed(3)} ≥ ${HL_STOP}，回退到 ${chosen_bright}`);
                            break;
                        }
                        chosen_bright = bright;
                    }
                    if (chosen_bright !== params.bright) {
                        console.log(`[LUT-算法-标准-高光放行提亮] bright ${params.bright} → ${chosen_bright}`);
                    }
                    params.bright = chosen_bright;
                } else {
                    if (params.bright >= BRIGHT_CAP) {
                        console.log(`[LUT-算法-标准-高光放行提亮] 未触发：bright=${params.bright} ≥ ${BRIGHT_CAP}（已封顶）`);
                    } else {
                        console.log(`[LUT-算法-标准-高光放行提亮] 未触发：当前高光=${_hl_now.toFixed(3)} ≥ ${HL_START}`);
                    }
                }
            }
        }

        // ---- Build 278 逐帧安全闸（仅在会出问题的帧上生效）; Build 280 preset scale + relaxed aesthetic limits ----
        if (skinPixels !== null && skinPixels.length > 0) {
            const preset = activePreset();
            withPresetSafety(preset, () => {
                safetyGuard(params, globalSample || null, coarse);
                if (preset.scale !== 1) {
                    for (const k of ['temp', 'tint', 'sat', 'bright', 'contrast', 'highlight', 'shadow']) {
                        params[k] = Math.round(params[k] * preset.scale);
                    }
                    safetyGuard(params, globalSample || null, coarse);
                }
            });
        }

        // ---- 非有限值兜底 ----
        for (const k of ['temp', 'tint', 'sat', 'bright', 'contrast', 'highlight', 'shadow']) {
            if (!isFinite(params[k]) || isNaN(params[k])) {
                params[k] = template[k] || 0;
            }
        }

        return params;
    }

    // ============================================================
    // 三、LUT 烘焙
    // ============================================================
    function generateLutData(size, params) {
        const data = new Float32Array(size * size * size * 3);
        const toeSlope = shadowToeSlope(params);
        let idx = 0;
        for (let b = 0; b < size; b++) {
            for (let g = 0; g < size; g++) {
                for (let r = 0; r < size; r++) {
                    let rIn = r / (size - 1);
                    let gIn = g / (size - 1);
                    let bIn = b / (size - 1);

                    let t = applyBrightnessScalar(rIn, gIn, bIn, params.bright);
                    rIn = t[0]; gIn = t[1]; bIn = t[2];
                    t = applyHighlightShadowScalar(rIn, gIn, bIn, params.highlight, params.shadow);
                    rIn = t[0]; gIn = t[1]; bIn = t[2];
                    t = applyContrastScalar(rIn, gIn, bIn, params.contrast);
                    rIn = t[0]; gIn = t[1]; bIn = t[2];
                    t = applySaturationScalar(rIn, gIn, bIn, params.sat);
                    rIn = t[0]; gIn = t[1]; bIn = t[2];
                    t = applyTempTintScalar(rIn, gIn, bIn, params.temp, params.tint);
                    rIn = t[0]; gIn = t[1]; bIn = t[2];

                    if (CONFIG.shoulder.enabled) {
                        t = applyHighlightShoulder(rIn, gIn, bIn); rIn = t[0]; gIn = t[1]; bIn = t[2];
                    } else {
                        const lum = KR * rIn + KG * gIn + KB * bIn;
                        if (lum > OVEREXPOSE_LIMIT && !isNearWhite(rIn, gIn, bIn)) {
                            const s = OVEREXPOSE_LIMIT / lum;
                            rIn *= s; gIn *= s; bIn *= s;
                        }
                    }

                    const r0 = r / (size - 1), g0 = g / (size - 1), b0 = b / (size - 1);
                    let t2 = applyShadowToe(r0, g0, b0, rIn, gIn, bIn, toeSlope);
                    t2 = applyWhiteAnchor(r0, g0, b0, t2[0], t2[1], t2[2]);
                    rIn = t2[0]; gIn = t2[1]; bIn = t2[2];

                    data[idx++] = Math.min(1, Math.max(0, rIn));
                    data[idx++] = Math.min(1, Math.max(0, gIn));
                    data[idx++] = Math.min(1, Math.max(0, bIn));
                }
            }
        }
        return data;
    }
    function shadowToeSlope(params) {
        const ST = CONFIG.shadowToe;
        const T = ST.toeEnd;
        let t = applyBrightnessScalar(T, T, T, params.bright);
        t = applyHighlightShadowScalar(t[0], t[1], t[2], params.highlight, params.shadow);
        t = applyContrastScalar(t[0], t[1], t[2], params.contrast);
        t = applySaturationScalar(t[0], t[1], t[2], params.sat);
        t = applyTempTintScalar(t[0], t[1], t[2], params.temp, params.tint);
        const outT = KR * t[0] + KG * t[1] + KB * t[2];
        const cap = params.shadow > ST.shadowForWide ? ST.slopeMaxShadow : ST.slopeMax;
        return Math.max(ST.slopeMin, Math.min(cap, outT / T));
    }

    function applyWhiteAnchor(r0, g0, b0, r, g, b) {
        const WA = CONFIG.whiteAnchor;
        if (!WA.enabled) return [r, g, b];
        const lin = KR * r0 + KG * g0 + KB * b0;
        if (lin <= WA.lumLo) return [r, g, b];
        const mx = Math.max(r0, g0, b0), mn = Math.min(r0, g0, b0);
        const sat = mx > 1e-6 ? (mx - mn) / mx : 0;
        if (sat >= WA.satHi) return [r, g, b];
        const sm = (e0, e1, x) => { const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t); };
        const w = sm(WA.lumLo, WA.lumHi, lin) * (1 - sm(WA.satLo, WA.satHi, sat));
        const lout = KR * r + KG * g + KB * b;
        if (w <= 0 || lout <= 1e-6) return [r, g, b];
        // keep the colour correction (white balance), restore the source luminance
        const k = 1 + (lin / lout - 1) * w;
        return [r * k, g * k, b * k];
    }

    function applyShadowToe(r0, g0, b0, r, g, b, slope) {
        const ST = CONFIG.shadowToe;
        const lin = KR * r0 + KG * g0 + KB * b0;
        if (lin >= ST.toeEnd) return [r, g, b];
        let w = 1;
        if (lin > ST.toeFull) {
            const x = (lin - ST.toeFull) / (ST.toeEnd - ST.toeFull);
            w = 1 - x * x * (3 - 2 * x);
        }
        const tr = r0 * slope, tg = g0 * slope, tb = b0 * slope;
        return [r + (tr - r) * w, g + (tg - g) * w, b + (tb - b) * w];
    }
// Build 278: strided whole-frame RGB sample for the per-frame safety check.
function globalSample(data, aw, ah) {
 const n = aw * ah, want = CONFIG.safety.globalSamplePixels;
 const step = Math.max(1, Math.floor(n / want));
 const out = new Float32Array(Math.floor((n + step - 1) / step) * 3);
 let j = 0;
 for (let p = 0; p < n && j + 2 < out.length; p += step) {
  const i = p * 4; out[j++] = data[i] / 255; out[j++] = data[i + 1] / 255; out[j++] = data[i + 2] / 255;
 }
 return j === out.length ? out : out.slice(0, j);
}
function computeGlobalHlRatio(data, step) {
        const nPix = data.length / 4;
        let hl = 0, cnt = 0;
        const s = step || 1;
        for (let i = 0; i < data.length; i += 4 * s) {
            const r = data[i] / 255, g = data[i + 1] / 255, b = data[i + 2] / 255;
            const lum = KR * r + KG * g + KB * b;
            if (lum > HL_THRESHOLD) hl++;
            cnt++;
        }
        if (cnt === 0) return 0;
        return hl / cnt;
    }
function computeRegionCrRange(data, aw, ah, region, coverage, fallback) {
        const x1 = region.x1, y1 = region.y1, x2 = region.x2, y2 = region.y2;
        const totalPix = (x2 - x1) * (y2 - y1);
        if (totalPix <= 0) return { range: fallback };
        const step = Math.max(1, Math.floor(Math.sqrt(totalPix / 40000)));
        const crList = [];
        for (let y = y1; y < y2; y += step) {
            for (let x = x1; x < x2; x += step) {
                const i = (y * aw + x) * 4;
                const r = data[i], g = data[i + 1], b = data[i + 2];
                const cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
                crList.push(cr);
            }
        }
        if (crList.length === 0) return { range: fallback };
        crList.sort((a, b) => a - b);
        const total = crList.length;
        const lowIdx = Math.floor(total * (1 - coverage) / 2);
        const highIdx = Math.min(total - 1, Math.floor(total * (1 + coverage) / 2));
        let crMin = Math.floor(crList[lowIdx]);
        let crMax = Math.ceil(crList[highIdx]);
        crMin = Math.max(120, crMin);
        crMax = Math.min(190, crMax);
        if (crMax - crMin < 30) return { range: fallback };
        return { range: [crMin, crMax] };
    }
function isSkinColorRegion(r, g, b, crRange, cbRange) {
        if (r < g - 4) return false;
        if (g < b - 4) return false;
        if (r <= b) return false;
        const rb = r / Math.max(b, 1);
        if (rb > 2.0) return false;
        const rg = r / Math.max(g, 1);
        if (rg > 1.6) return false;
        const cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
        const cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
        if (cb < cbRange[0] || cb > cbRange[1]) return false;
        if (cr < crRange[0] || cr > crRange[1]) return false;
        const y = 0.299 * r + 0.587 * g + 0.114 * b;
        if (y < 30 || y > 250) return false;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        if (max < 20) return false;
        const sat = (max - min) / max;
        if (sat < 0.08 || sat > 0.55) return false;
        return true;
    }
function sampleFrame(data, aw, ah, faceBox) {
 const faceDetected = !!faceBox;
 const full_hl_ratio_global = computeGlobalHlRatio(data, CONFIG.globalHlSampleStep);
        let sampleRegion;
        let regionName;
        if (faceDetected && faceBox) {
            sampleRegion = faceBox;
            regionName = '人脸框';
        } else {
            const cw = Math.floor(aw * 0.5);
            const ch = Math.floor(ah * 0.5);
            const cx0 = Math.floor((aw - cw) / 2);
            const cy0 = Math.floor((ah - ch) / 2);
            sampleRegion = { x1: cx0, y1: cy0, x2: cx0 + cw, y2: cy0 + ch };
            regionName = '中央50%';
        }

        console.log(
            `[LUT-路由] 人脸检测=${faceDetected ? '有' : '无'} → 采样区域【${regionName}】 ` +
            `[${sampleRegion.x1},${sampleRegion.y1} ${sampleRegion.x2},${sampleRegion.y2}]`
        );

        const isCenterFallback = !faceDetected;
        const FACE_SKIN_LUM_MAX_EFF = isCenterFallback ? 0.72 : FACE_SKIN_LUM_MAX;
        console.log(`[LUT-采样] 采样区域=${isCenterFallback ? '中央50%' : '人脸框'}，FACE_SKIN_LUM_MAX=${FACE_SKIN_LUM_MAX_EFF}`);

        const crInfo = computeRegionCrRange(
            data, aw, ah, sampleRegion,
            CONFIG.skinDetection.crCoverage,
            CONFIG.skinDetection.fallbackCrRange
        );
        const crRange = crInfo.range;
        const cbRange = CONFIG.skinDetection.staticCbRange;

        const temp = [];
        const highTemp = [];
        const rx1 = sampleRegion.x1, ry1 = sampleRegion.y1;
        const rx2 = sampleRegion.x2, ry2 = sampleRegion.y2;

        for (let y = ry1; y < ry2; y++) {
            for (let x = rx1; x < rx2; x++) {
                const i = (y * aw + x) * 4;
                const r = data[i], g = data[i + 1], b = data[i + 2];

                const lum = KR * r / 255 + KG * g / 255 + KB * b / 255;
                if (lum > CONFIG.highLumThreshold) {
                    highTemp.push(r / 255, g / 255, b / 255);
                }

                if (lum >= FACE_SKIN_LUM_MAX_EFF) continue;
                if (!isSkinColorRegion(r, g, b, crRange, cbRange)) continue;
                temp.push(r / 255, g / 255, b / 255);
            }
        }

        console.log(`[LUT-区域肤色] Cr范围=[${crRange[0]},${crRange[1]}] 区域内肤色像素=${temp.length / 3}`);

        if (temp.length / 3 < CONFIG.faceBoxMinSkinPixels) {
            console.log(`[LUT-区域肤色] 采样区域内肤色像素不足: ${temp.length / 3} < ${CONFIG.faceBoxMinSkinPixels}，放弃本次`);
            return { pixels: null, box: faceBox, high_rb: 1.0, high_pixels: 0, full_hl_ratio_global, regionName };
        }

        let highRB = 1.0;
        const highPixels = highTemp.length / 3;
        if (highPixels >= CONFIG.highPixelMinCount) {
            const highArr = new Float32Array(highTemp);
            const highStats = sampleSkinStats(highArr);
            if (highStats) highRB = highStats.skin_rb;
        }

        console.log(`[LUT-路由] 采用【${regionName}】结果，N = ${temp.length / 3}`);

        return {
            pixels: new Float32Array(temp),
            box: faceBox,
            high_rb: highRB,
            high_pixels: highPixels,
            full_hl_ratio_global,
            regionName,
        };
    }


function analyzeFrame(bytes, width, height, box) {
 const raster = new Uint8ClampedArray(bytes);
 const frame = sampleFrame(raster, width, height, box);
 if (!frame.pixels) return null;
 frame.global_sample = globalSample(raster, width, height);
 const info = sampleSkinStats(frame.pixels);
 info.full_hl_ratio = frame.full_hl_ratio_global;
 info.high_rb = frame.high_rb; info.high_pixels = frame.high_pixels;
 info.regionName = frame.regionName;
 // v6.7.8: remove forceHighMatch / condFace backdoors; route solely via classifiers.
 const useExtreme = isExtremeDark(info);
 const useHighMatch = useExtreme ? false : isHighMatch(info);
 return {params: predictParams(info, subsample(frame.pixels, CONFIG.maxSkinPixels), useExtreme, useHighMatch, frame.global_sample), info: info, stage: useExtreme ? '极端暗部' : useHighMatch ? '高命中' : '标准'};
}
// Bounded multi-frame path (userscript v6.7.8): prefer face-box frames, median skin stats, merge pixels.
// Caller supplies up to CONFIG.sampleFrames (3) RGBA rasters; grab/timing lives in native Swift.
// Scene-change guard (build 274): if skin_lum / skin_rb span across frames exceeds thresholds,
// do not median mixed scenes — keep the largest coherent cluster (face-preferred), or best single.
const SCENE_GUARD_LUM_SPAN = 0.08;
const SCENE_GUARD_RB_SPAN = 0.18;
function selectCoherentPairs(pairs) {
 if (pairs.length <= 1) return { pairs: pairs, sceneGuard: false };
 let minL = Infinity, maxL = -Infinity, minR = Infinity, maxR = -Infinity;
 for (const p of pairs) {
  minL = Math.min(minL, p.stats.skin_lum); maxL = Math.max(maxL, p.stats.skin_lum);
  minR = Math.min(minR, p.stats.skin_rb); maxR = Math.max(maxR, p.stats.skin_rb);
 }
 if ((maxL - minL) <= SCENE_GUARD_LUM_SPAN && (maxR - minR) <= SCENE_GUARD_RB_SPAN) {
  return { pairs: pairs, sceneGuard: false };
 }
 // Largest cluster: each seed keeps frames within thresh on both axes; tie → earliest seed.
 let bestIdx = [0];
 for (let seed = 0; seed < pairs.length; seed++) {
  const s0 = pairs[seed].stats;
  const cluster = [];
  for (let i = 0; i < pairs.length; i++) {
   const s = pairs[i].stats;
   if (Math.abs(s.skin_lum - s0.skin_lum) <= SCENE_GUARD_LUM_SPAN &&
       Math.abs(s.skin_rb - s0.skin_rb) <= SCENE_GUARD_RB_SPAN) {
    cluster.push(i);
   }
  }
  if (cluster.length > bestIdx.length ||
      (cluster.length === bestIdx.length && cluster[0] < bestIdx[0])) {
   bestIdx = cluster;
  }
 }
 return { pairs: bestIdx.map(i => pairs[i]), sceneGuard: true };
}
function analyzeMultiFrame(frames) {
 if (!frames || !frames.length) return null;
 const sampled = [];
 for (let i = 0; i < frames.length; i++) {
  const f = frames[i];
  if (!f || f.bytes == null || !f.width || !f.height) continue;
  const box = (f.box === undefined || f.box === null) ? null : f.box;
  const raster = new Uint8ClampedArray(f.bytes);
  const frame = sampleFrame(raster, f.width | 0, f.height | 0, box);
  if (frame && frame.pixels) { frame.global_sample = globalSample(raster, f.width | 0, f.height | 0); sampled.push(frame); }
 }
 if (!sampled.length) return null;
 const faceFrames = sampled.filter(f => f.regionName === '人脸框');
 const used = faceFrames.length > 0 ? faceFrames : sampled;
 const pairs = [];
 for (const f of used) {
  const s = sampleSkinStats(f.pixels);
  if (s) pairs.push({ frame: f, stats: s });
 }
 if (!pairs.length) return null;
 const selected = selectCoherentPairs(pairs);
 const chosen = selected.pairs;
 const perFrameStats = chosen.map(p => p.stats);
 const firstFrame = chosen[0].frame;
 const globalHlRatio = firstFrame.full_hl_ratio_global !== undefined
  ? firstFrame.full_hl_ratio_global : 0;
 const info = {
  skin_rb: median(perFrameStats.map(s => s.skin_rb)),
  skin_rg: median(perFrameStats.map(s => s.skin_rg)),
  skin_lum: median(perFrameStats.map(s => s.skin_lum)),
  skin_sat: median(perFrameStats.map(s => s.skin_sat)),
  full_contrast: median(perFrameStats.map(s => s.full_contrast)),
  full_hl_ratio: globalHlRatio,
  full_sh_ratio: median(perFrameStats.map(s => s.full_sh_ratio)),
  high_rb: firstFrame.high_rb !== undefined ? firstFrame.high_rb : 1.0,
  high_pixels: firstFrame.high_pixels !== undefined ? firstFrame.high_pixels : 0,
  regionName: firstFrame.regionName || '人脸框',
 };
 let totalLen = 0;
 for (const p of chosen) totalLen += p.frame.pixels.length;
 const merged = new Float32Array(totalLen);
 let off = 0;
 for (const p of chosen) { merged.set(p.frame.pixels, off); off += p.frame.pixels.length; }
 const useExtreme = isExtremeDark(info);
 const useHighMatch = useExtreme ? false : isHighMatch(info);
 const stage = useExtreme ? '极端暗部' : useHighMatch ? '高命中' : '标准';
 return {
  params: predictParams(info, subsample(merged, CONFIG.maxSkinPixels), useExtreme, useHighMatch, firstFrame.global_sample),
  info: info,
  stage: stage,
  frameCount: chosen.length,
  rawFrameCount: sampled.length,
  usedFace: faceFrames.length > 0,
  sceneGuard: selected.sceneGuard
 };
}
function cubeRGBA(values) {
 const keys = ['temp','tint','sat','bright','contrast','highlight','shadow'];
 const params = {}; keys.forEach((k,i)=>params[k]=values[i]);
 const rgb = generateLutData(33,params); const out = new Float32Array(33*33*33*4);
 for(let i=0,j=0;i<rgb.length;i+=3,j+=4) {out[j]=rgb[i];out[j+1]=rgb[i+1];out[j+2]=rgb[i+2];out[j+3]=1;}
 return Array.from(out);
}

return {analyzeFrame, analyzeMultiFrame, cubeRGBA, setPreset, activePreset, withPresetSafety, applyShadowToe, applyWhiteAnchor, globalShape, shadowToeSlope, meanHueSat, renderArray, safetyGuard, safetyFailure, safetyContext, globalSample, CONFIG, sampleFrame, sampleSkinStats, predictParams, generateLutData, applyParamsToSkinArray, computeRegionCrRange, isSkinColorRegion, isExtremeDark, isHighMatch, computeGlobalHlRatio, median, selectCoherentPairs, SCENE_GUARD_LUM_SPAN, SCENE_GUARD_RB_SPAN};
})();
