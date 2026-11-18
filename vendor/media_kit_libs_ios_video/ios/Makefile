all: Frameworks/Mpv.xcframework Frameworks/.symlinks

# libmpv with the avfoundation video output (patch/), built from MPVKit's
# sources; CI keeps it in its cache, keyed on these files.
.libmpv/libmpv.a: mpvkit.lock build_libmpv.sh $(wildcard patch/*.patch)
	sed -i '' 's/\r$$//g' build_libmpv.sh
	bash build_libmpv.sh mpvkit.lock .libmpv
	touch .libmpv/libmpv.a

Frameworks/Mpv.xcframework: mpvkit.lock build_mpv_framework.sh .libmpv/libmpv.a
	mkdir -p Frameworks
	sed -i '' 's/\r$$//g' build_mpv_framework.sh create_framework_symlinks.sh
	LIBMPV=$(CURDIR)/.libmpv bash build_mpv_framework.sh mpvkit.lock .cache Frameworks/Mpv.xcframework
	touch Frameworks/Mpv.xcframework

Frameworks/.symlinks: Frameworks/Mpv.xcframework
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv

.PHONY: clean
clean:
	rm -rf .cache .libmpv Frameworks
