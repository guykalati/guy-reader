APP_NAME = Guy_reader.app
BUILD_DIR = $(APP_NAME)/Contents
MACOS_DIR = $(BUILD_DIR)/MacOS
RESOURCES_DIR = $(BUILD_DIR)/Resources

CC = clang
CFLAGS = -fobjc-arc -O2 -Wall
FRAMEWORKS = -framework Cocoa -framework WebKit -framework AVFoundation -framework Carbon

all: bundle

$(MACOS_DIR)/Guy_reader: src/main.m src/speech_engine.m src/speech_engine.h src/reading_origin.m src/reading_origin.h
	@mkdir -p $(MACOS_DIR)
	$(CC) $(CFLAGS) $(FRAMEWORKS) src/main.m src/speech_engine.m src/reading_origin.m -o $(MACOS_DIR)/Guy_reader

bundle: $(MACOS_DIR)/Guy_reader
	@mkdir -p $(RESOURCES_DIR)/ui
	@cp src/Info.plist $(BUILD_DIR)/Info.plist
	@cp -r src/ui/* $(RESOURCES_DIR)/ui/
	@if [ -f "AppIcon.icns" ]; then cp AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns; fi
	@codesign -s - --force --deep -i com.guy.guyreader $(APP_NAME) 2>/dev/null || true
	@echo "Build successful: $(APP_NAME) created!"

clean:
	rm -rf $(APP_NAME) GlaidoReader.app tests/run_test_speech_engine

test:
	@$(CC) $(CFLAGS) -framework Cocoa -framework ApplicationServices src/reading_origin.m tests/test_clicked_origin.m -o tests/run_test_clicked_origin
	@tests/run_test_clicked_origin
	@rm -f tests/run_test_clicked_origin
	@node --test tests/test_reader_playback.js tests/test_extension_playback.js
	@$(CC) $(CFLAGS) $(FRAMEWORKS) src/speech_engine.m src/reading_origin.m tests/test_reader_coordinator.m -o tests/run_test_reader_coordinator
	@tests/run_test_reader_coordinator
	@rm -f tests/run_test_reader_coordinator
	@mkdir -p tests
	@$(CC) $(CFLAGS) -framework Cocoa -framework AVFoundation src/speech_engine.m tests/test_speech_engine.m -o tests/run_test_speech_engine
	@tests/run_test_speech_engine
	@rm -f tests/run_test_speech_engine
	@osascript -l JavaScript tests/test_smart_extractor.js
	@echo "All test suites passed successfully!"
