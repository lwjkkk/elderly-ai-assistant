import io, os

workdir = os.environ.get('APP_WORKDIR', '')
assert workdir, 'set APP_WORKDIR'
p = workdir + '/app_flutter/lib/afu/afu_chat_page.dart'
t = io.open(p, encoding='utf-8').read()

def rep(old, new):
    global t
    assert old in t, 'missing: ' + old[:60]
    t = t.replace(old, new, 1)

rep("      tipIsWeather.value = false;",
    "      _setTipWeather(false);")
rep("      tipIsWeather.value = true;",
    "      _setTipWeather(true);")
rep("  static Future<String?> _load() async {",
    """  static void _setTipWeather(bool v) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (tipIsWeather.value != v) tipIsWeather.value = v;
    });
  }

  static Future<String?> _load() async {""")

io.open(p, 'w', encoding='utf-8', newline='').write(t)
print('notifier deferred past build')
