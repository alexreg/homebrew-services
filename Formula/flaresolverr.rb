class Flaresolverr < Formula
  require "language/node"

  desc "Proxy server to bypass Cloudflare protection"
  homepage "https://github.com/FlareSolverr/FlareSolverr"
  url "https://github.com/FlareSolverr/FlareSolverr/archive/refs/tags/v2.2.10.tar.gz"
  sha256 "6d45c38d1118cfd64eac53898c6d3305c39927831663e452808a3df675109858"
  license "MIT"
  head "https://github.com/FlareSolverr/FlareSolverr.git", branch: "master"

  depends_on "node@16"

  def node
    deps.reject(&:build?)
        .map(&:to_formula)
        .find { |f| f.name.match?(/^node(@\d+(\.\d+)*)?$/) }
  end

  def install
    libexec.install Dir["*"]

    cd libexec do
      ENV["PUPPETEER_SKIP_DOWNLOAD"] = "1"
      system "npm", "install", *Language::Node.local_npm_install_args
      system "npm", "run", "build"
    end

    puppeteer_download_path = var/"flaresolverr/puppeteer"
    puppeteer_download_path.mkpath

    (bin/"flaresolverr").write <<~EOS
      #!/bin/bash
      DEFAULT_PUPPETEER_EXECUTABLE_PATH=(${PUPPETEER_DOWNLOAD_PATH:-"#{puppeteer_download_path}"}/*/Firefox*.app/Contents/MacOS/firefox)
      export PUPPETEER_EXECUTABLE_PATH="${PUPPETEER_EXECUTABLE_PATH:-$DEFAULT_PUPPETEER_EXECUTABLE_PATH}"
      export PUPPETEER_PRODUCT="${PUPPETEER_PRODUCT:-firefox}"
      exec "#{node.opt_bin}/node" "#{libexec}/dist/server.js" "$@"
    EOS

    (bin/"flaresolverr-install-browser").write <<~EOS
      #!/bin/bash

      cd "#{libexec}" || exit

      export PUPPETEER_DOWNLOAD_PATH="${PUPPETEER_DOWNLOAD_PATH:-"#{puppeteer_download_path}"}"
      export PUPPETEER_PRODUCT="${PUPPETEER_PRODUCT:-firefox}"

      OPTIND=1
      while getopts "hr" opt; do
        case "$opt" in
          h)
            echo "usage: $(basename $0) [-h] [-r]"
            echo "  -h    show help"
            echo "  -r    remove existing browser and reinstall"
            exit 0
            ;;
          r)
            if [[ -d "$PUPPETEER_DOWNLOAD_PATH" ]]; then
              rm -rf "$PUPPETEER_DOWNLOAD_PATH" || exit
              echo "Removed existing local browser installation."
            fi
            ;;
        esac
      done &&
      shift $(( OPTIND - 1 ))
      [[ "$1" == "--" ]] && shift

      # Install nightly version of Firefox required by Puppeteer.
      exec "#{node.opt_bin}/node" node_modules/puppeteer/install.js
    EOS

    # Replace universal binaries with native slices
    deuniversalize_machos
  end

  def caveats
    <<~EOS
      Before you can use flaresolverr, you must run `flaresolverr-install-browser` to locally install a nightly version of Firefox.
    EOS
  end

  plist_options startup: true
  service do
    run "#{bin}/flaresolverr"
    environment_variables CAPTCHA_SOLVER: "none", LOG_HTML: "false", LOG_LEVEL: "info"
    keep_alive true
    log_path var/"log/flaresolverr.log"
    error_log_path var/"log/flaresolverr.log"
  end

  test do
    ENV["PUPPETEER_DOWNLOAD_PATH"] = testpath/"puppeteer"

    system opt_bin/"flaresolverr-install-browser"
    firefox = Pathname.glob(testpath/"puppeteer/*/Firefox Nightly.app/Contents/MacOS/firefox").first
    assert(!firefox.nil?)
    assert_predicate firefox, :executable?
    assert_match "Mozilla Firefox", shell_output("\"#{firefox}\" -v")

    (testpath/"test.exp").write <<~EOS
      spawn "#{opt_bin}/flaresolverr"
      set timeout 3
      expect {
        -exact "INFO FlareSolverr v#{version}" { exit 0 }
        timeout { exit 1 }
        eof { exit 1 }
      }
    EOS
    system "expect", "-f", "test.exp"
  end
end
