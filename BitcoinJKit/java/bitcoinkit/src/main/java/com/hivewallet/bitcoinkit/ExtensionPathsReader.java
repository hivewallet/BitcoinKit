package com.hivewallet.bitcoinkit;

class ExtensionPathsReader {
    public static void main(String[] args) {
        String[] paths = System.getProperty("java.ext.dirs").split(":");
        StringBuilder buffer = new StringBuilder();

        for (String path : paths) {
            if (path.startsWith("/System")) {
                if (buffer.length() > 0) {
                    buffer.append(":");
                }

                buffer.append(path);
            }
        }
 
        System.out.print(buffer.toString());
    }
}
