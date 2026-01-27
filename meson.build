project(
  'gentoo-functions', 'c',
  version: '1.7.3',
  license: [
    'GPL-2.0-only',
    'MIT'
  ],
  default_options : [
    'warning_level=2',
    'c_std=gnu11',
  ]
)

install_data(
  'functions.sh',
  install_dir: 'lib/gentoo'
)

install_subdir(
  'functions',
  install_dir: 'lib/gentoo'
)

cc = meson.get_compiler('c')

executable(
  'consoletype',
  'consoletype.c',
  install: true
)

executable(
  'shquote',
  'shquote.c',
  install: true
)

install_man(
  'consoletype.1',
)

do_tests = get_option('tests')
if do_tests
  test(
    'test-functions', files('test-functions'),
    workdir : meson.current_source_dir(),
    protocol : 'tap',
    verbose : true,
    env : { 'BUILD_DIR' : meson.current_build_dir() }
  )
endif
