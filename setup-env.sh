xcode_bin_path=$(dirname $(xcodebuild -find clang))
export PATH=$xcode_bin_path:$PATH
