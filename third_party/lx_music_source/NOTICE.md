# LX source compatibility assets

Mesting 1.0.61 pins the eleven scripts reported green on 2026-11-05 01:09
(Asia/Shanghai) by <https://github.com/pdone/lx-music-source>, commit
`000578ddca4a676012cf735abdc3489efdc67c74`. Original script bytes and author
headers are retained. Per-file sizes and SHA256 are in `upstream.json`.

These are third-party scripts collected by that repository; its availability
report tests HTTP hosts, not full playback, download permission, every quality,
or service reliability. Inclusion does not establish rights to every recording.
Respect provider limits: in particular Huibq and Yuningxi prohibit rapid bulk
downloads. Mesting uses a single streaming download worker and bounded probes.

The scripts run only in isolated local WebView documents with all ordinary
network/resource access blocked by CSP. Only `wy` / `musicUrl` is invoked.
The host provides bounded anonymous HTTP and selected LX utilities, without
NetEase/Kugou cookies, sessions, account identifiers or device credentials.
External update notifications are ignored; scripts cannot update themselves.
Mesting's bridge and transport restrictions may make some upstream paths
unavailable; a green upstream badge is never treated as media verification.

`bridge.js` is Mesting integration code. `crypto-js/crypto-js.js` is the original
CryptoJS 4.2.0 bundle, MIT licensed; its complete license is in
`crypto-js/LICENSE`. No blanket license is asserted for the collected scripts.
Upstream author and license statements are preserved rather than replaced.
