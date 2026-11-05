# Local secure-storage patch

Based on flutter_secure_storage 10.3.1 (BSD-3-Clause; see package/LICENSE).
The original Dart API, storage names, key aliases and cipher algorithms remain
compatible. Android commits credential/key metadata before reporting success,
schedules independent namespaces independently, and returns a fixed error family
instead of credential-bearing exception messages. Global Pub cache is unchanged.
