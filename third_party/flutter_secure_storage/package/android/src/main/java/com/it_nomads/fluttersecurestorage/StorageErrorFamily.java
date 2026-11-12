package com.it_nomads.fluttersecurestorage;

/** Safe cause classification. Never returns exception text or a class name. */
final class StorageErrorFamily {
    static String of(Throwable error) {
        String family = "unknown";
        int priority = 0;
        for (int depth = 0; error != null && depth < 12; depth++, error = error.getCause()) {
            String type = error.getClass().getSimpleName();
            if (type.equals("KeyPermanentlyInvalidatedException")) return "keyInvalidated";
            if (type.equals("BadPaddingException") || type.equals("AEADBadTagException") ||
                    type.equals("IllegalBlockSizeException")) {
                family = "decrypt"; priority = 3;
            } else if (priority < 2 && (type.equals("UnrecoverableKeyException") ||
                    type.equals("InvalidKeyException") || type.equals("UserNotAuthenticatedException"))) {
                family = "keyUnavailable"; priority = 2;
            } else if (priority < 1 && (error instanceof java.io.IOException || error instanceof SecureCommitException)) {
                family = "io"; priority = 1;
            }
        }
        return family;
    }
}
