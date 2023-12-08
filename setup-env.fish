set xcode_bin_path $(dirname $(xcodebuild -find clang))
fish_add_path $xcode_bin_path
