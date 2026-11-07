# Mesting Beta.12 optical correction, Beta.13 hooks and Beta.15 geometry isolation

## Beta.19 geometry and Android offscreen-pass correction

`LiquidGlassRenderObject.performLayout` invalidates the matte when its actual
size changes, rather than on every parent layout request. Shape/style/relative
geometry invalidation stays independent. No optical parameters are reduced.

`enclosingBackdropPassRect` also recognizes enabled `ImageFilterLayer` render
boundaries used by Material 3 stretch. Stationary composites still call the
transform tracker because a filter can change the enclosing pass without a
render transform change. The layer caches both transform and pass rect before
updating shader uniforms. Premium blur, refraction, frost, gesture deformation
and stretch remain enabled. Application pages must paint the intended backdrop
inside isolated filters; a Scaffold behind the filter is not automatically
available to nested backdrop readers.

The physical Android benchmark and color samples are documented in
`docs/fixes-2026-10-27-beta19.md`. Software raster tests alone do not certify
Impeller output, and no constant 120fps or process CPU percentage is claimed.

## Beta.15 navigation morph work isolation

`package/lib/src/widgets/surfaces/tab_bar_searchable_layout.dart` retains the
existing premium `AdaptiveLiquidGlassLayer` outside height animation callbacks.
Accessory motion also reuses its optical/content subtree on both animated axes.
The renderer, shader, quality, blur, refraction, springs, geometry targets and
input/RTL/search contracts remain intact. Application-owned capsule content now
receives its compact placement explicitly instead of rebuilding at every width.

The host widget benchmark for one identical collapse sequence changes optical
layer rebuilds from 14 to 1 and artwork rebuilds from 19 to 1. These are rebuild
counts, not Android GPU timing or a guarantee of a particular device frame rate.

## Beta.13 host-owned text editing

`widgets/surfaces/shared/glass_search_bar_config.dart` adds nullable
`contextMenuBuilder` and `selectionControls` hooks. The searchable tab's
`src/widgets/surfaces/tab_bar_searchable_internal.dart` passes them to its
CupertinoTextField. When absent, upstream Cupertino toolbar/handle defaults
remain. The application supplies the same editing menu and blue controls as
its other fields without importing application business code into this vendor.
This does not modify the Beta.12 shader or lower optical quality.

## Beta.12 optical correction (preserved)

The `package/` folder vendors liquid_glass_widgets 1.15.0, under its MIT license.
The application's dependency override uses this directory so the APK and source
archive contain exactly the same renderer. The installed Pub cache is unchanged.

Changed upstream file: `shaders/lightweight_glass.frag`.

The fallback shader previously added a 0.65 base perimeter, plus a dark-only
minimum rim floor, independently of directional light and Fresnel settings.
Dark surfaces therefore looked uniformly outlined even with fresnelStrength=0.
The patch suppresses those two constant perimeter terms for dark backdrop luma.
Directional specular lobes, refractive displacement, chromatic dispersion,
meniscus absorption, touch feedback, body tint and light-mode calibration remain.

The premium renderer is not replaced. At the application level, adaptive quality
is disabled to honor the requirement that scrolling must retain premium optics.
The shared blue action uses the upstream clear body mode (alpha tint with
specular/refraction) to prevent light-background luminance normalization from
turning its normal blue into pale cyan.

Verification distinguishes software-renderer captures from actual device GPU
evidence. A successful host capture does not certify Android native refraction.

## Beta.20 keyboard hit bounds

In `tab_bar_searchable_layout.dart`, the accessory wrapper includes the focused
search pill's keyboard extent in its layout height. The inner pill already
reserves and paints that extent; the previous shorter wrapper rejected pointers
at the visible raised field and let the body behind it receive them. This patch
changes the ancestor hit bounds, with no second keyboard translation and no
change to optical quality, press/drag springs, accessory morphing or shaders.
Host regression taps the visible field with and without an accessory across
keyboard heights 100, 280, 180 and zero, and checks that the body receives none.

## Music 1.0.6 spring subtree retention

`tab_bar_searchable_layout.dart` passes the search pill and complete tab
indicator as stable `ListenableBuilder.child` subtrees. Spring ticks change
their positioned bounds without reconstructing the text field, input selection
machinery or optical controls. Height morphs still update their real dimensions.
`tab_bar_searchable_internal.dart` also retains the expanded input subtree
across width-only LayoutBuilder updates, including its invisible collapsed state.
Quality, shaders, magnification, drag/press springs and accessory geometry remain.
The 336-frame host comparison at 8333 microseconds per pump records structural
work only; Android GPU timing and physical 120Hz delivery require device checks.

## Music 1.0.7 capture and content reuse

The background capture boundary now shares a full-DPR GPU image within each
interaction frame. Every lens owns a cloned image handle. A fresh frame gets
a fresh image even when a nested repaint boundary or video texture updates
without repainting its parent, so dynamic wallpapers remain live. This removes
duplicate fullscreen `toImageSync` work without
changing material parameters, resolution, refraction or shader quality.

The accessory wrapper gives the tab/search bar a stable bottom-aligned viewport
while its outer bounds move. Selected tab glyph/label subtrees are retained
through intensity transforms and invalidated for configuration/dependency
changes. The same host scenario measures 21426 widget builds versus 22726 in
1.0.6; it remains structural evidence rather than Android 120fps certification.

## Music 1.0.8 raster work and opt-in diagnostics

The dispersion shader reuses four RGBA texels only when the RGB coordinates
share the exact same 2x2 footprint. Each channel retains its own bilinear
fractions and alpha-over-fallback operation; different footprints retain the
original path. Aberration, full-resolution sampling and material values stay.
The host pixel test compiles the actual helpers for SkSL/GLES/GLES3/Vulkan and
compares edge/alpha/footprint cases with the frozen 1.0.7 formula.

The accessory and bar opt into a strict peer group only at a settled expanded
endpoint. Geometry/keyboard/search/fade transitions close the accessory gate.
The opt-in fade keeps a single render object and clears retained shared keys
before changing opacity. Ordinary opacity remains a barrier. A strict group
checks current translation-only transforms, shadow bounds and blur read outsets;
overlapping, scaled, backed, captured or frosted surfaces stay independent.
Retained-layer composition clears all strict peer keys if a press makes the
group unsafe. The overlapping tab indicator retains its existing isolation.
Light-mode shadows may prevent sharing, which is intentional to preserve pixels.

`glass_render_diagnostics.dart` offers disabled-by-default, bounded counters for
CPU paint work, matte rebuild/cache/pixels, live/baked shadows, live blur/shader
passes and full-DPR captures. These are not GPU-pass or presented-FPS counters.
App diagnostics aligns raw vsync and transition brackets and drains 1.2 seconds
after Stop. Only user-run Xiaomi 14 Pro tests can establish the device speedup;
host pump counts and pixel references do not certify sustained 120 fps.

## 2026-10-28 page-scoped search input (local, unreleased)

`SearchPillState` rebinds external text/focus owners when its configuration
changes. It removes listeners from the previous owner, preserves caller-owned
objects, and synchronizes focus with the outer layout after the frame. The
same persistent glass field can therefore serve music and audiobook searches
without leaking typed text, focus, or recreating the bar's motion controllers.
Only input ownership changes; existing optics and morph parameters are kept.

## 2026-10-28 page button scroll cancellation (local, unreleased)

`GlassButton.persistPressOnDrag` defaults to false for scrolling page actions.
The opt-in true path retains free-drag distortion. `LiquidStretch` forwards
`cancelOnDrag` and `enabled` to `GlassDragBuilder`: crossing tap slop cancels
the spring for that pointer until lift-off, in addition to cancelling the
optical press. Raw drag listeners therefore cannot keep a page button inflated
after its containing ListView takes ownership. Separate fingers cannot steal
an active press; disabling also clears the in-flight optical animation.

`fadeWhenDisabled` separates disabled interaction from lens opacity. Its true
default preserves the package's disabled fade; Mesting's shared action/button
wrappers choose false with genuinely disabled hit testing, focus and semantics.
No spring timing, refraction quality, blur setting or tab-bar morph is removed.
