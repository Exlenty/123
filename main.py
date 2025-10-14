import undetected_chromedriver as uc
import time
import pathlib
import os
import sys
import stat
import traceback
from selenium.common.exceptions import WebDriverException

STDIN = None
STDOUT = None
STDERR = None

# --- Configuration ---
USER_PROFILE_PATH = pathlib.Path("./chrome_profile/")
TARGET_URL = "https://idx.google.com/noxy-panel-59774499"  # укажи нужный URL
IDLE_TIME_SECONDS = 60
CHROME_BINARY_PATH = "./chrome/chrome"

chrome_lib_path = os.path.join(os.getcwd(), 'chrome')
libs_path = os.path.join(os.getcwd(), 'libs')
current_ld_path = os.environ.get('LD_LIBRARY_PATH', '')

if STDIN is not None:
    sys.stdin = open(STDIN, "r")
if STDOUT is not None:
    sys.stdout = open(STDOUT, "w")
if STDERR is not None:
    sys.stderr = open(STDERR, "w")

if current_ld_path:
    os.environ['LD_LIBRARY_PATH'] = f"{libs_path}:{chrome_lib_path}:{current_ld_path}"
else:
    os.environ['LD_LIBRARY_PATH'] = f"{libs_path}:{chrome_lib_path}"

# Создание профиля, если нет
if not USER_PROFILE_PATH.exists():
    USER_PROFILE_PATH.mkdir(parents=True)

def run_session(is_headless: bool):
    chrome_binary_abs = os.path.abspath(CHROME_BINARY_PATH)

    if not os.path.exists(chrome_binary_abs):
        print(f"Error: Chrome binary not found at '{chrome_binary_abs}'.", file=sys.stderr)
        return

    os.chmod(chrome_binary_abs, os.stat(chrome_binary_abs).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    options = uc.ChromeOptions()
    options.binary_location = chrome_binary_abs

    # Основные флаги для работы в контейнере
    options.add_argument("--no-first-run")
    options.add_argument("--no-default-browser-check")
    options.add_argument("--disable-extensions")
    options.add_argument("--disable-popup-blocking")
    options.add_argument("--disable-background-timer-throttling")
    options.add_argument("--disable-backgrounding-occluded-windows")
    options.add_argument("--disable-renderer-backgrounding")
    options.add_argument("--disable-gpu")
    options.add_argument("--disable-software-rasterizer")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--single-process")
    options.add_argument("--no-sandbox")
    options.add_argument(f"--user-data-dir={os.path.abspath(USER_PROFILE_PATH)}")

    if is_headless:
        options.add_argument("--headless=new")

    driver = None
    try:
        print(f"Starting Chrome (headless={is_headless}) using: {chrome_binary_abs}")
        driver = uc.Chrome(options=options, version_main=None, driver_executable_path=None)
        print(f"Navigating to {TARGET_URL}...")
        driver.get(TARGET_URL)
        time.sleep(IDLE_TIME_SECONDS)
        print("Idle complete.")
    except WebDriverException as e:
        print(f"WebDriver error: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
    finally:
        if driver:
            try:
                driver.quit()
                print("Chrome closed.")
            except Exception as e:
                print(f"Error closing Chrome: {e}", file=sys.stderr)

def verify_chrome_installation():
    chrome_binary_abs = os.path.abspath(CHROME_BINARY_PATH)
    libs_abs = os.path.abspath('./libs')

    if not os.path.exists(chrome_binary_abs):
        print(f"Chrome binary not found at: {chrome_binary_abs}")
        return False
    if not os.access(chrome_binary_abs, os.X_OK):
        print(f"Chrome binary is not executable: {chrome_binary_abs}")
        return False

    try:
        import subprocess
        env = os.environ.copy()
        result = subprocess.run([chrome_binary_abs, "--version"], capture_output=True, text=True, timeout=10, env=env)
        if result.returncode == 0:
            print(f"Chrome version: {result.stdout.strip()}")
            return True
        else:
            print(f"Chrome failed to run: {result.stderr}")
            return False
    except Exception as e:
        print(f"Error running Chrome: {e}")
        return False

if __name__ == "__main__":
    print("=== Chrome Automation Script Starting ===")
    print(f"Working directory: {os.getcwd()}")
    print(f"Chrome binary path: {os.path.abspath(CHROME_BINARY_PATH)}")
    print(f"Libs directory: {os.path.abspath('./libs')}")
    print(f"LD_LIBRARY_PATH set to: {os.environ['LD_LIBRARY_PATH']}\n")

    if not verify_chrome_installation():
        print("Chrome verification failed. Exiting.", file=sys.stderr)
        sys.exit(1)

    try:
        while True:
            run_session(is_headless=True)
            print("\n--- Cycle complete. Waiting 10 seconds before next cycle. ---")
            time.sleep(10)
    except KeyboardInterrupt:
        print("Script interrupted.")
        sys.exit(0)
    except Exception as e:
        print(f"Fatal error: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)
