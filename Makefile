.PHONY: build release run test app clean

build:
	swift build

release:
	swift build -c release

run:
	swift run -c release MacDjView

test:
	swift run MacDjView --test example.djvu

app: release
	./scripts/make-app-bundle.sh
	@echo "Run with: open MacDjView.app"

clean:
	swift package clean
	rm -rf MacDjView.app
