# Local HTTPS regression fixture

This self-signed certificate and its deliberately public test key are synthetic
fixtures for loopback-only tests. They are unrelated to application signing,
Android Keystore, user accounts or any public server.

The certificate is valid from 2020-01-01 through 2040-01-01 for
`music.fixture.test`, `images.fixture.test`, `official.fixture.test` and
`localhost`. Tests trust it only in their disposable Dart process and resolve
the fixture names to loopback through a mock Android method channel. Nothing
is installed in the operating system's trust store or used by production code.
