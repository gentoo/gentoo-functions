project(
  'gentoo-functions', 'c',
  version: '0.20',
  license: 'GPL-2.0-only',
  default_options : [
    'warning_level=2',
    'c_std=gnu11',
  ]
)

conf_data = configuration_data()
conf_data.set('version', meson.project_version())
# For now, we can't really use libexec, given everyone hardcodes /lib/gentoo.
# We might be able to install some symlinks to get around this though?
conf_data.set('GENTOO_LIBEXEC_DIR', get_option('prefix') / 'lib' / 'gentoo')

configure_file(
  input: 'functions.sh.in',
  output: 'functions.sh',
  configuration: conf_data,
  install: true,
  install_dir: 'lib/gentoo'
)

cc = meson.get_compiler('c')

executable(
  'consoletype',
  'consoletype.c',
  install: true
)

install_man(
  'consoletype.1',
)

executable(
  'ecma48-cpr',
  'ecma48-cpr.c',
  install: true,
  install_dir: get_option('prefix') / 'lib' / 'gentoo'
)

do_tests = get_option('tests')
if do_tests
  test(
    'test-functions', files('test-functions'),
    workdir : meson.current_build_dir(),
  )
endif
