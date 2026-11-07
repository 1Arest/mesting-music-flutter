# On-device Qishui web authentication

Pinned reference: mytv-android/myMusic commit
`5a9a4cbde079d205776117c772c4ee77dd742ae0`, with its upstream
sodahub-org/libresoda commit `5edd2ff3b825f0a16b1e281204822ee06842df9c`.
Exact downloaded assets, URLs and SHA256 values are in PROVENANCE.json.

The 1.0.66 QR-only adapter also follows the complete per-QR web parameters and
storage nonce initialization in mytv-android/myMusic commit
`9c0f1f0ccb1b1046306f61c50998e327c040a6bc`, SodaQrLogin.kt / SodaQrSigner.kt.
The pinned libresoda dependency remains `5edd2ff3b825f0a16b1e281204822ee06842df9c`.
All four security host/SDK/verification assets were checked byte-identical to
that Android reference; they have not been modified.

- security_host.html is libresoda's AGPL-3.0 security host; soda_verify.html is
  myMusic's AGPL-3.0 Android adaptation. The copied files remain unchanged.
- sdk-glue.js and bdms.js are the upstream-bundled official Soda Music web
  security components. Their provenance is retained; inclusion does not claim
  that these components are independently authored or licensed under AGPL.
- react.js/react-dom.js are React 17.0.2, Copyright Facebook, Inc. and its
  affiliates, MIT. See LICENSE-REACT-MIT.txt and their embedded notices.
- QishuiWebAuthPlugin.kt and qishui_qr_login.dart adapt the referenced flow for
  Mesting's lifecycle and account model. AGPL-3.0 source/reference notices are
  retained with the complete source delivery.

Mesting modifications: native request/domain allowlists; no public signer or
server; scoped Qishui-cookie cleanup instead of global cookie deletion; no
fabricated mobile installation IDs; isolated disposable transaction; explicit
MFA action; authenticated profile verification before encrypted commit; and
separate PC/Web versus mobile credential routing. The native host injects a
Qishui-origin storage reset before SDK initialization; source assets are not
rewritten. No device/login success is implied by the presence of these files.
