import undetected_chromedriver as uc
import time
import pathlib
import os
import sys
import stat
import traceback
from selenium.common.exceptions import WebDriverException
import subprocess

# --- Configuration ---
USER_PROFILE_PATH = pathlib.Path("./chrome_profile/")
TARGET_URL = "https://idx.google.com/noxy-panel-59774499"  # <-- вставь нужный URL
IDLE_TIME_SECONDS = 60
CHROME_BINARY_PATH = "./chrome/chrome"
CHROMEDRIVER_PATH = "./chrome/chromedriver"
LIBS_PATH = "./libs"

# --- Set LD_LIBRARY_PATH ---
chrome_lib_path = os.path.abspath('./chrome')
libs_path = os.path.abspath(LIBS_PATH)
current_ld_path = os.environ.get('LD_LIBRARY_PATH', '')
if current_ld_path:
    os.environ['LD_LIBRARY_PATH'] = f"{libs_path}:{chrome_lib_path}:{current_ld_path}"
else:
    os.environ['LD_LIBRARY_PATH'] = f"{libs_path}:{chrome_lib_path}"

# --- Ensure user profile exists ---
if not USER_PROFILE_PATH.exists():
    USER_PROFILE_PATH.mkdir(parents=True)

# --- Verify Chrome installation ---
def verify_chrome_installation():
    chrome_bin = os.path.abspath(CHROME_BINARY_PATH)
    driver_bin = os.path.abspath(CHROMEDRIVER_PATH)

    if not os.path.exists(chrome_bin):
        print(f"Chrome binary not found at: {chrome_bin}")
        return False
    if not os.access(chrome_bin, os.X_OK):
        os.chmod(chrome_bin, os.stat(chrome_bin).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    
    if not os.path.exists(driver_bin):
        print(f"Chromedriver not found at: {driver_bin}")
        return False
    if not os.access(driver_bin, os.X_OK):
        os.chmod(driver_bin, os.stat(driver_bin).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    # Check Chrome version
    try:
        env = os.environ.copy()
        env['LD_LIBRARY_PATH'] = os.environ['LD_LIBRARY_PATH']
        result = subprocess.run([chrome_bin, '--version'], capture_output=True, text=True, timeout=10, env=env)
        if result.returncode == 0:
            print(f"Chrome version: {result.stdout.strip()}")
            return True
        else:
            print(f"Chrome failed to run: {result.stderr}")
            return False
    except Exception as e:
        print(f"Error checking Chrome: {e}")
        return False

# --- Run browser session ---
def run_session(is_headless: bool):
    chrome_bin = os.path.abspath(CHROME_BINARY_PATH)
    driver_bin = os.path.abspath(CHROMEDRIVER_PATH)
    user_data_abs = os.path.abspath(USER_PROFILE_PATH)

    options = uc.ChromeOptions()
    options.binary_location = chrome_bin
    options.add_argument(f"--user-data-dir={user_data_abs}")
    options.add_argument("--no-first-run")
    options.add_argument("--no-default-browser-check")
    options.add_argument("--disable-extensions")
    options.add_argument("--disable-popup-blocking")
    options.add_argument("--disable-gpu")
    options.add_argument("--disable-software-rasterizer")
    options.add_argument("--disable-background-timer-throttling")
    options.add_argument("--disable-backgrounding-occluded-windows")
    options.add_argument("--disable-renderer-backgrounding")
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    if is_headless:
        options.add_argument("--headless=new")

    driver = None
    try:
        print(f"Starting Chrome session (headless={is_headless})...")
        driver = uc.Chrome(
            options=options,
            driver_executable_path=driver_bin,
            version_main=141
        )
        print(f"Navigating to {TARGET_URL} ...")
        driver.get(TARGET_URL)
        time.sleep(IDLE_TIME_SECONDS)
        print("Session complete.")
    except WebDriverException as e:
        print(f"WebDriverException: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
    finally:
        if driver:
            try:
                print("Closing browser...")
                driver.quit()
            except Exception as e:
                print(f"Error closing driver: {e}", file=sys.stderr)

# --- Main ---
if __name__ == "__main__":
    print("=== Chrome Automation Script Starting ===")
    if not verify_chrome_installation():
        print("Chrome verification failed. Exiting.", file=sys.stderr)
        sys.exit(1)

    print("All checks passed. Starting automation loop...\n")

    try:
        while True:
            run_session(is_headless=True)  # <-- можно False для визуального режима
            print("\n--- Cycle complete. Waiting 10 seconds before next cycle. ---\n")
            time.sleep(10)
    except KeyboardInterrupt:
        print("Script interrupted by user. Exiting.")
        sys.exit(0)
    except Exception as e:
        print(f"Fatal error: {e}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)
