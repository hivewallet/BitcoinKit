package org.slf4j.impl;

import org.slf4j.ILoggerFactory;
import org.slf4j.Logger;

import java.util.HashMap;
import java.util.Map;

// based on http://javaeenotes.blogspot.com/2011/12/custom-slf4j-logger-adapter.html

public class CocoaLoggerFactory implements ILoggerFactory
{
    private Map<String, CocoaLogger> loggerMap;

    public CocoaLoggerFactory()
    {
        loggerMap = new HashMap<String, CocoaLogger>();
    }

    @Override
    public Logger getLogger(String name)
    {
        synchronized (loggerMap)
        {
            if (!loggerMap.containsKey(name))
            {
                loggerMap.put(name, new CocoaLogger(name));
            }

            return loggerMap.get(name);
        }
    }
}
