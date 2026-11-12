"""Compile the actual pinned selector in release/profile/slim configurations.

Only Android/Flutter types outside this small function are stubbed. Keeping the
function's source and preprocessor guards intact catches the production-only
failure that an application-side test or a profile engine would miss.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('--compiler', default='c++')
    args = parser.parse_args()
    source = args.source.read_text(encoding='utf-8')
    start = source.index('AndroidRenderingAPI FlutterMain::SelectedRenderingAPI(')
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    actual_function = source[start:end]
    prefix = r'''
#include <cassert>
#include <iostream>
#include <string>
#define FML_CHECK(value) if (!(value)) std::cerr
namespace flutter {
enum class AndroidRenderingAPI { kSoftware, kSkiaOpenGLES, kImpellerOpenGLES, kImpellerVulkan, kImpellerAutoselect };
struct Settings { bool enable_software_rendering = false; bool enable_impeller = true; std::string requested_rendering_backend; };
constexpr int kMinimumAndroidApiLevelForImpeller = 29;
bool vivante = false;
bool IsVivante() { return vivante; }
class FlutterMain { public: static AndroidRenderingAPI SelectedRenderingAPI(const Settings&, int); };
'''
    suffix = r'''
} // namespace flutter
int main() {
  using namespace flutter;
  using API = AndroidRenderingAPI;
  auto select = [](Settings s, int api = 36) { return FlutterMain::SelectedRenderingAPI(s, api); };
  Settings s;
  assert(select(s) == API::kImpellerAutoselect);
#if !SLIMPELLER
  s.requested_rendering_backend = "opengles";
  assert(select(s) == API::kImpellerOpenGLES);
  assert(select(s, 24) == API::kImpellerOpenGLES);
  s.enable_impeller = false;
  assert(select(s) == API::kSkiaOpenGLES);
  s.enable_software_rendering = true;
  assert(select(s) == API::kSoftware);
  s = Settings();
  assert(select(s, 28) == API::kSkiaOpenGLES);
  vivante = true;
  assert(select(s) == API::kSkiaOpenGLES);
  vivante = false;
  s.requested_rendering_backend = "vulkan";
#ifdef FLUTTER_RELEASE
  assert(select(s, 28) == API::kSkiaOpenGLES);
  assert(select(s) == API::kImpellerAutoselect);
#else
  assert(select(s, 28) == API::kImpellerVulkan);
  assert(select(s) == API::kImpellerVulkan);
#endif
  s.requested_rendering_backend = "unknown";
  assert(select(s) == API::kImpellerAutoselect);
#else
  s.requested_rendering_backend = "opengles";
  assert(select(s) == API::kImpellerAutoselect);
  s.enable_impeller = false;
  assert(select(s) == API::kImpellerAutoselect);
#endif
}
'''
    with tempfile.TemporaryDirectory(prefix='mesting-engine-selector-') as temp:
        root = Path(temp)
        cpp = root / 'selector.cc'
        cpp.write_text(prefix + actual_function + suffix, encoding='utf-8')
        variants = [
            ('release', ['-DFLUTTER_RELEASE=1', '-DSLIMPELLER=0'], 10),
            ('profile', ['-DSLIMPELLER=0'], 10),
            ('slim-release', ['-DFLUTTER_RELEASE=1', '-DSLIMPELLER=1'], 3),
        ]
        for name, defines, cases in variants:
            binary = root / name
            subprocess.run([args.compiler, '-std=c++17', '-O2', *defines, str(cpp), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)
            print(f'{name}: {cases} selector assertions passed')


if __name__ == '__main__':
    main()
