package com.it_nomads.fluttersecurestorage;

/** Cause families are exported, never messages, aliases or decrypted values. */
public class Release154StorageFamilyTest {
    static class KeyPermanentlyInvalidatedException extends java.security.InvalidKeyException {}
    static void expect(String expected, Throwable error) {
        if (!expected.equals(StorageErrorFamily.of(error))) throw new AssertionError(expected);
    }
    public static void main(String[] args) {
        expect("decrypt", new javax.crypto.BadPaddingException("private fixture"));
        expect("decrypt", new java.io.IOException("wrapper", new javax.crypto.BadPaddingException()));
        expect("keyInvalidated", new Exception("wrapper", new KeyPermanentlyInvalidatedException()));
        expect("keyUnavailable", new java.security.InvalidKeyException());
        expect("io", new SecureCommitException());
        expect("unknown", new Exception("BadPaddingException is only text, not a cause"));
        System.out.println("6 native credential-family scenarios passed");
    }
}
