all: Frameworks/Mpv.xcframework Frameworks/.symlinks

Frameworks/Mpv.xcframework: mpvkit.lock build_mpv_framework.sh
	mkdir -p Frameworks
	sed -i '' 's/\r$$//g' build_mpv_framework.sh create_framework_symlinks.sh
	bash build_mpv_framework.sh mpvkit.lock .cache Frameworks/Mpv.xcframework
	touch Frameworks/Mpv.xcframework

Frameworks/.symlinks: Frameworks/Mpv.xcframework
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv

.PHONY: clean
clean:
	rm -rf .cache Frameworks
