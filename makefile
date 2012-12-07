all: build_swf

build_swf:
	/usr/local/flex_sdk_4.6/bin/mxmlc SWFUpload.as -o SWFUpload.swf
	cp SWFUpload.swf /Users/jianbin/developer/ganji/ganji_sta/src/swf/SWFUpload-2.swf