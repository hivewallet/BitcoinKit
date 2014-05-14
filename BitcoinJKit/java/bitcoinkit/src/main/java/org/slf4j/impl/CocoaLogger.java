package org.slf4j.impl;

import org.slf4j.Logger;
import org.slf4j.helpers.FormattingTuple;
import org.slf4j.helpers.MarkerIgnoringBase;
import org.slf4j.helpers.MessageFormatter;

// based on http://javaeenotes.blogspot.com/2011/12/custom-slf4j-logger-adapter.html and JDK14LoggerAdapter

public class CocoaLogger extends MarkerIgnoringBase implements Logger {
    public static final int HILoggerLevelNotSet = -1;
    public static final int HILoggerLevelDebug = 1;
    public static final int HILoggerLevelInfo = 2;
    public static final int HILoggerLevelWarn = 3;
    public static final int HILoggerLevelError = 4;

    private static String SELF = CocoaLogger.class.getName();
    private static String SUPER = MarkerIgnoringBase.class.getName();

    private static int globalLevel = HILoggerLevelDebug;
    private int level = HILoggerLevelNotSet;

    public static int getGlobalLevel() {
        return globalLevel;
    }

    public static void setGlobalLevel(int newLevel) {
        globalLevel = newLevel;
    }

    CocoaLogger(String name) {
        this.name = name;
    }

    public int getLevel() {
        return (level == HILoggerLevelNotSet) ? globalLevel : level;
    }

    public void setLevel(int newLevel) {
        level = newLevel;
    }

    public boolean isTraceEnabled() {
        return getLevel() <= HILoggerLevelDebug;
    }

    public void trace(String msg) {
        if (isTraceEnabled()) {
            log(SELF, HILoggerLevelDebug, msg, null);
        }
    }

    public void trace(String format, Object arg) {
        if (isTraceEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg);
            log(SELF, HILoggerLevelDebug, ft.getMessage(), ft.getThrowable());
        }
    }

    public void trace(String format, Object arg1, Object arg2) {
        if (isTraceEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg1, arg2);
            log(SELF, HILoggerLevelDebug, ft.getMessage(), ft.getThrowable());
        }
    }

    public void trace(String format, Object... argArray) {
        if (isTraceEnabled()) {
            FormattingTuple ft = MessageFormatter.arrayFormat(format, argArray);
            log(SELF, HILoggerLevelDebug, ft.getMessage(), ft.getThrowable());
        }
    }

    public void trace(String msg, Throwable t) {
        if (isTraceEnabled()) {
            log(SELF, HILoggerLevelDebug, msg, t);
        }
    }

    public boolean isDebugEnabled() {
        return getLevel() <= HILoggerLevelDebug;
    }

    public void debug(String msg) {
        if (isDebugEnabled()) {
            log(SELF, HILoggerLevelDebug, msg, null);
        }
    }

    public void debug(String format, Object arg) {
        if (isDebugEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg);
            log(SELF, HILoggerLevelDebug, ft.getMessage(), ft.getThrowable());
        }
    }

    public void debug(String format, Object arg1, Object arg2) {
        if (isDebugEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg1, arg2);
            log(SELF, HILoggerLevelDebug, ft.getMessage(), ft.getThrowable());
        }
    }

    public void debug(String format, Object... argArray) {
        if (isDebugEnabled()) {
            FormattingTuple ft = MessageFormatter.arrayFormat(format, argArray);
            log(SELF, HILoggerLevelDebug, ft.getMessage(), ft.getThrowable());
        }
    }

    public void debug(String msg, Throwable t) {
        if (isDebugEnabled()) {
            log(SELF, HILoggerLevelDebug, msg, t);
        }
    }

    public boolean isInfoEnabled() {
        return getLevel() <= HILoggerLevelInfo;
    }

    public void info(String msg) {
        if (isInfoEnabled()) {
            log(SELF, HILoggerLevelInfo, msg, null);
        }
    }

    public void info(String format, Object arg) {
        if (isInfoEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg);
            log(SELF, HILoggerLevelInfo, ft.getMessage(), ft.getThrowable());
        }
    }

    public void info(String format, Object arg1, Object arg2) {
        if (isInfoEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg1, arg2);
            log(SELF, HILoggerLevelInfo, ft.getMessage(), ft.getThrowable());
        }
    }

    public void info(String format, Object... argArray) {
        if (isInfoEnabled()) {
            FormattingTuple ft = MessageFormatter.arrayFormat(format, argArray);
            log(SELF, HILoggerLevelInfo, ft.getMessage(), ft.getThrowable());
        }
    }

    public void info(String msg, Throwable t) {
        if (isInfoEnabled()) {
            log(SELF, HILoggerLevelInfo, msg, t);
        }
    }

    public boolean isWarnEnabled() {
        return getLevel() <= HILoggerLevelWarn;
    }

    public void warn(String msg) {
        if (isWarnEnabled()) {
            log(SELF, HILoggerLevelWarn, msg, null);
        }
    }

    public void warn(String format, Object arg) {
        if (isWarnEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg);
            log(SELF, HILoggerLevelWarn, ft.getMessage(), ft.getThrowable());
        }
    }

    public void warn(String format, Object arg1, Object arg2) {
        if (isWarnEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg1, arg2);
            log(SELF, HILoggerLevelWarn, ft.getMessage(), ft.getThrowable());
        }
    }

    public void warn(String format, Object... argArray) {
        if (isWarnEnabled()) {
            FormattingTuple ft = MessageFormatter.arrayFormat(format, argArray);
            log(SELF, HILoggerLevelWarn, ft.getMessage(), ft.getThrowable());
        }
    }

    public void warn(String msg, Throwable t) {
        if (isWarnEnabled()) {
            log(SELF, HILoggerLevelWarn, msg, t);
        }
    }

    public boolean isErrorEnabled() {
        return getLevel() <= HILoggerLevelError;
    }

    public void error(String msg) {
        if (isErrorEnabled()) {
            log(SELF, HILoggerLevelError, msg, null);
        }
    }

    public void error(String format, Object arg) {
        if (isErrorEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg);
            log(SELF, HILoggerLevelError, ft.getMessage(), ft.getThrowable());
        }
    }

    public void error(String format, Object arg1, Object arg2) {
        if (isErrorEnabled()) {
            FormattingTuple ft = MessageFormatter.format(format, arg1, arg2);
            log(SELF, HILoggerLevelError, ft.getMessage(), ft.getThrowable());
        }
    }

    public void error(String format, Object... arguments) {
        if (isErrorEnabled()) {
            FormattingTuple ft = MessageFormatter.arrayFormat(format, arguments);
            log(SELF, HILoggerLevelError, ft.getMessage(), ft.getThrowable());
        }
    }

    public void error(String msg, Throwable t) {
        if (isErrorEnabled()) {
            log(SELF, HILoggerLevelError, msg, t);
        }
    }

    private void log(String callerFQCN, int level, String msg, Throwable t) {
        String fileName = null;
        String methodName = null;
        int lineNumber = 0;

        StackTraceElement callerData = getCallerData(callerFQCN);
        if (callerData != null) {
            fileName = callerData.getFileName();
            lineNumber = callerData.getLineNumber();

            String className = callerData.getClassName().replaceAll(".*\\.", "");
            methodName = "[" + className + " " + callerData.getMethodName() + "]";
        }

        if (msg != null) {
            receiveLogFromJVM(fileName, methodName, lineNumber, level, msg);
        }

        if (t != null) {
            receiveLogFromJVM(fileName, methodName, lineNumber, level, "Exception logged: " + t);
        }
    }

    // TODO
    private StackTraceElement getCallerData(String callerFQCN) {
        StackTraceElement[] steArray = new Throwable().getStackTrace();

        int selfIndex = -1;
        for (int i = 0; i < steArray.length; i++) {
            final String className = steArray[i].getClassName();
            if (className.equals(callerFQCN) || className.equals(SUPER)) {
                selfIndex = i;
                break;
            }
        }

        int found = -1;
        for (int i = selfIndex + 1; i < steArray.length; i++) {
            final String className = steArray[i].getClassName();
            if (!(className.equals(callerFQCN) || className.equals(SUPER))) {
                found = i;
                break;
            }
        }

        if (found != -1) {
            return steArray[found];
        } else {
            return null;
        }
    }

    public native void receiveLogFromJVM(String fileName, String methodName, int lineNumber, int level, String msg);
}
