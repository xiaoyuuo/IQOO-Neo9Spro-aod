package com.dsh.neoaod;

import android.app.AndroidAppHelper;
import android.app.Application;
import android.os.Message;

import java.io.File;
import java.io.FileWriter;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * Neo9SP_AOD · LSPosed 模块
 *
 * 只做一件事：让「熄屏显示」(com.vivo.nightpearl) 认为本机支持全屏 AOD，
 * 并在设置页露出「局部/全屏」选择器。
 *
 * 属性 (ro.vivo.keyguard_full_aod.enable) 与面板能力串 (/sys/lcm/aod_disp_info)
 * 由配套的 KSU 模块负责，本模块不碰文件系统。
 *
 * MIT License · 作者：酷安@小雨爱分享
 */
public class Main implements IXposedHookLoadPackage {

    private static final String TAG = "[NeoAOD]";
    private static final String KEY_FULL_AOD = "ro.vivo.keyguard_full_aod.enable";
    private static File logFile;

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) {
        final String pkg = lpparam.packageName;
        if ("com.vivo.nightpearl".equals(pkg)) {
            hookProp(lpparam.classLoader);
            hookAodAnimation(lpparam.classLoader);
            forceBool("r4.h", lpparam.classLoader, "Q");
            forceBool("r4.h", lpparam.classLoader, "e0");
            forceBool("r4.h", lpparam.classLoader, "f0");
        } else if ("com.android.systemui".equals(pkg)) {
            // 作用域默认只勾「熄屏显示」；这里保留是为了手动勾上 SystemUI 时也能用
            hookProp(lpparam.classLoader);
        }
    }

    /** 把 ro.vivo.keyguard_full_aod.enable 的读取结果顶成 "1" */
    private void hookProp(ClassLoader cl) {
        XC_MethodHook hook = new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                if (param.args.length >= 1 && (param.args[0] instanceof String)
                        && KEY_FULL_AOD.equals(param.args[0])) {
                    log("prop.get(" + KEY_FULL_AOD + ") = " + param.getResult() + " -> \"1\"");
                    param.setResult("1");
                }
            }
        };
        try {
            XposedHelpers.findAndHookMethod("android.os.SystemProperties", cl, "get",
                    String.class, String.class, hook);
        } catch (Throwable t) {
            log("hook FAIL SystemProperties.get(2): " + t);
        }
        try {
            XposedHelpers.findAndHookMethod("android.os.SystemProperties", cl, "get",
                    String.class, hook);
        } catch (Throwable t) {
            log("hook FAIL SystemProperties.get(1): " + t);
        }
    }

    /** 丢掉 AOD 切换动画消息（what==0），避免整屏动画与硬切叠加 */
    private void hookAodAnimation(ClassLoader cl) {
        String[] targets = {"k5.a$c", "com.vivo.aod_keyguard.view.AodKeyguardViewContainer$g"};
        for (final String cls : targets) {
            try {
                XposedHelpers.findAndHookMethod(cls, cl, "handleMessage", Message.class,
                        new XC_MethodHook() {
                            @Override
                            protected void beforeHookedMethod(MethodHookParam param) {
                                Message msg = (Message) param.args[0];
                                if (msg == null) return;
                                log("aodAnim " + cls + " what=" + msg.what);
                                if (msg.what == 0) {
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

    /** 无条件把能力判定方法改成 true */
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

    static void log(String s) {
        String line = TAG + " " + s;
        XposedBridge.log(line);
        writeFile(line);
    }

    private static synchronized void writeFile(String line) {
        try {
            if (logFile == null) {
                Application app = AndroidAppHelper.currentApplication();
                if (app == null) return;
                File dir = app.getExternalFilesDir(null);
                if (dir == null) return;
                if (!dir.exists()) dir.mkdirs();
                logFile = new File(dir, "neoaod.log");
            }
            FileWriter fw = new FileWriter(logFile, true);
            try {
                fw.write(line + "\n");
            } finally {
                fw.close();
            }
        } catch (Throwable ignored) {
        }
    }
}
