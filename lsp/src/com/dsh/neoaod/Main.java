package com.dsh.neoaod;

import java.io.File;
import java.io.FileWriter;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage.LoadPackageParam;

/**
 * NeoAOD-lite v0.5
 *
 * 只钩「KSU 改不到的 Java 布尔」，属性与面板能力串全部交给 KSU 模块。
 *
 * 为什么还需要它：
 *   「熄屏类型（局部 / 全屏）」的选择器显示条件是 r4.h.f0()：
 *       modelNumber >= 2436 && n && x
 *   ro.vivo.product.model = PD2339 → modelNumber = 2339，天生过不了这一关。
 *   这是 vivo 写死的机型白名单，KSU 只能动属性和文件，钩不到这个 Java 判断。
 *
 * 钩的东西只有 4 个：
 *   r4.h.Q()  —— 面板 support_full_screen
 *   r4.h.e0() —— prop && 版本判断
 *   r4.h.f0() —— 机型白名单（关键那一个）
 *   SystemUI 的 VivoAodViewMediator.isFullAodType()
 */
public class Main implements IXposedHookLoadPackage {

    private static final String TAG = "[NeoAOD]";
    private static File logFile;

    @Override
    public void handleLoadPackage(LoadPackageParam lpp) {
        String pkg = lpp.packageName;
        if ("com.vivo.nightpearl".equals(pkg)) {
            hookProp(lpp.classLoader);
            hookAodAnimation(lpp.classLoader);
            forceBool("r4.h", lpp.classLoader, "Q");
            forceBool("r4.h", lpp.classLoader, "e0");
            forceBool("r4.h", lpp.classLoader, "f0");
        } else if ("com.android.systemui".equals(pkg)) {
            hookProp(lpp.classLoader);
        }
    }

    /** ro.vivo.keyguard_full_aod.enable 统一返回 "1"（反射读也走这里） */
    private void hookProp(ClassLoader cl) {
        XC_MethodHook h = new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                if (param.args.length < 1 || !(param.args[0] instanceof String)) return;
                if (!"ro.vivo.keyguard_full_aod.enable".equals(param.args[0])) return;
                log("prop.get(ro.vivo.keyguard_full_aod.enable) = " + param.getResult() + " -> \"1\"");
                param.setResult("1");
            }
        };
        try {
            XposedHelpers.findAndHookMethod("android.os.SystemProperties", cl, "get", String.class, String.class, h);
        } catch (Throwable t) {
            log("hook FAIL SystemProperties.get(2): " + t);
        }
        try {
            XposedHelpers.findAndHookMethod("android.os.SystemProperties", cl, "get", String.class, h);
        } catch (Throwable t) {
            log("hook FAIL SystemProperties.get(1): " + t);
        }
    }
    /**
     * 实验性：熄屏进 AOD 时会先黑一下再出面。
     * nightpearl 里 k5.a$c / AodKeyguardViewContainer$g 的 handleMessage 处理
     * MSG_START_KEYGUARD_TO_AOD_ANIMATION（what == 0）时会启动一次过渡动画。
     * 这里把 what==0 的消息丢弃，用来验证黑帧是否由这段动画造成（实测：无效，黑帧在显示层）。
     */
    private void hookAodAnimation(ClassLoader cl) {
        String[] classes = new String[]{
                "k5.a$c",
                "com.vivo.aod_keyguard.view.AodKeyguardViewContainer$g"
        };
        for (final String cls : classes) {
            try {
                XposedHelpers.findAndHookMethod(cls, cl, "handleMessage",
                        android.os.Message.class, new XC_MethodHook() {
                            @Override
                            protected void beforeHookedMethod(MethodHookParam param) {
                                android.os.Message m = (android.os.Message) param.args[0];
                                if (m == null) return;
                                log("aodAnim " + cls + " what=" + m.what);
                                if (m.what == 0) {
                                    log("aodAnim skip MSG_START_*_TO_AOD_ANIMATION");
                                    param.setResult(null);
                                }
                            }
                        });
                log("hook ok: " + cls + ".handleMessage");
            } catch (Throwable t) {
                log("hook FAIL " + cls + ".handleMessage: " + t);
            }
        }
    }

    private void forceBool(String cls, ClassLoader cl, final String method) {
        try {
            XposedHelpers.findAndHookMethod(cls, cl, method, new XC_MethodHook() {
                @Override
                protected void afterHookedMethod(MethodHookParam param) {
                    log("cap " + param.method.getDeclaringClass().getName() + "." + method
                            + "() = " + param.getResult() + " -> true");
                    param.setResult(Boolean.TRUE);
                }
            });
            log("hook ok: " + cls + "." + method + "()");
        } catch (Throwable t) {
            log("hook FAIL " + cls + "." + method + "(): " + t);
        }
    }

    static void log(String msg) {
        String line = TAG + " " + msg;
        XposedBridge.log(line);
        writeFile(line);
    }

    private static synchronized void writeFile(String line) {
        try {
            if (logFile == null) {
                android.app.Application app = android.app.AndroidAppHelper.currentApplication();
                if (app == null) return;
                File dir = app.getExternalFilesDir(null);
                if (dir == null) return;
                if (!dir.exists()) dir.mkdirs();
                logFile = new File(dir, "neoaod.log");
            }
            FileWriter w = new FileWriter(logFile, true);
            try {
                w.write(line + "\n");
            } finally {
                w.close();
            }
        } catch (Throwable ignored) {
        }
    }
}