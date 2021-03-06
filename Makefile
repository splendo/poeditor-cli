@all: clean build uninstall install

clean:
	rm -f poeditor-*.gem

build:
	gem build poeditor-cli.gemspec

uninstall:
	gem uninstall poeditor-cli --all --executables 2>/dev/null

install:
	gem install poeditor-*.gem

push: clean build
	gem push poeditor-*.gem
