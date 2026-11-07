package com.it_nomads.fluttersecurestorage;

/** Fixed, value-free failure for a native preferences commit returning false. */
public final class SecureCommitException extends IllegalStateException {
    public SecureCommitException() { super("Secure preferences commit failed"); }
}
