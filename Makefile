build_name := multiplayer-tictactoe
package := com.galviagames.multitictactoe

.PHONY: install-android
install-android:
	adb install ./build/armv7-android/${build_name}/${build_name}.apk

.PHONY: logs-android
logs-android:
	adb logcat -c
	adb logcat | grep DEBUG:SCRIPT:

.PHONY: run-android
run-android:
	adb shell monkey -p "${package}" -c android.intent.category.LAUNCHER 1

.PHONY: run
run: install-android run-android logs-android

.PHONY: clean-android
clean-android:
	docker run -v $(PWD):/app/${build_name} -w /app/${build_name} ${build_name}/bob -v --platform=armv7-android --archive clean
	chown $(whoami):$(whoami) -R ./build

.PHONY: build-android
build-android:
	docker run -v $(PWD):/app/${build_name} -w /app/${build_name} ${build_name}/bob -v --platform=armv7-android --variant debug --settings production.ini --archive build
	chown $(whoami):$(whoami) -R ./build

.PHONY: bundle-android
bundle-android:
	docker run -v $(PWD):/app/${build_name} -w /app/${build_name} ${build_name}/bob -v --platform=armv7-android --variant debug --settings production.ini --bundle-output=build/armv7-android --bundle-format=apk bundle

.PHONY: android
android: clean-android build-android bundle-android install-android run-android logs-android

.PHONY: quick-android
quick-android: build-android bundle-android install-android run-android logs-android

.PHONY: build-html
build-html:
	docker run -v $(PWD):/app/${build_name} -w /app/${build_name} ${build_name}/bob -v --platform=js-web --variant debug --settings production.ini --archive clean build
	chown $(whoami):$(whoami) -R ./build

.PHONY: html-prod
html-prod: build-html
	docker run -v $(PWD)/:/app/${build_name}/ -w /app/${build_name} ${build_name}/bob -v --platform=js-web --variant debug --settings production.ini --bundle-output=build/js-web bundle

.PHONY: deploy
deploy:
	surge ./build/js-web/${build_name} https://multitictactoe.galviagames.com

.PHONY: build-docker
build-docker:
	docker build -t ${build_name}/bob ./bob
