#!/usr/bin/env python3

import re
import subprocess
from datetime import datetime
import argparse
from typing import Tuple

# 1. Before running, make sure you create an API key from App Store Connect
#     (App Store Connect -> Users and Access -> Integrations -> App Store Connect API) and store the downloaded key in ~/.private_keys
# 2. Then set the following environment variables:
#     XCODE_API_KEY="API_KEY_ID"
#     XCODE_API_ISSUER="API_ISSUER_ID"
#
#     Find both of these values in App Store Connect web after creating the API key


def archive_application(platform: str, render_github_actions: bool = False):
    scheme = "Roam"
    project_path = "."
    archive_path = f"{project_path}/Archives/XCArchives/{platform}.xcarchive"
    print(f"Archiving application for platform {platform}")
    subprocess.run(
        f"xcodebuild archive -project {project_path}/Roam.xcodeproj -scheme {scheme} -archivePath {archive_path} -destination 'generic/platform={platform}' | xcbeautify{'' if render_github_actions else ' --renderer github-actions'}",
        shell=True,
    )
    print(f"Archive succeeded for platform {platform}")


def publish_to_app_store(
    platform: str, extension: str, render_github_actions: bool = False
):
    extensions = {
        "ios": "ipa",
        "tvos": "ipa",
        "macos": "pkg",
        "watchos": "ipa",
        "visionos": "ipa",
    }
    extension = extensions[platform.lower()]
    print(f"Publishing for platform {platform} with extension {extension}")
    subprocess.run(
        f"xcodebuild -exportArchive -archivePath ./Archives/XCArchives/{platform}.xcarchive -exportPath ./Archives/Exports/{platform} -exportOptionsPlist ./Scripts/options.plist | xcbeautify{'' if render_github_actions else ' --renderer github-actions'}",
        shell=True,
    )

    subprocess.run(
        f"xcrun altool --validate-app -f ./Archives/Exports/{platform}/Roam.{extension} -t {platform.lower()} --apiKey $XCODE_API_KEY --apiIssuer $XCODE_API_ISSUER",
        shell=True,
    )
    subprocess.run(
        f"xcrun altool --upload-app -f ./Archives/Exports/{platform}/Roam.{extension} -t {platform.lower()} --apiKey $XCODE_API_KEY --apiIssuer $XCODE_API_ISSUER",
        shell=True,
    )
    print(f"Publish succeeded for platform {platform}")


def get_current_versions() -> Tuple[str, str]:
    project_file_path = "./Roam.xcodeproj/project.pbxproj"

    with open(project_file_path, "r") as file:
        project_contents = file.readlines()

    marketing_version_line = [
        line
        for line in project_contents
        if re.search(r"MARKETING_VERSION = \d+\.\d+;", line)
    ]

    current_version_line = [
        line
        for line in project_contents
        if re.search(r"CURRENT_PROJECT_VERSION = \d+\.\w+\.\d+", line)
    ]

    if not marketing_version_line:
        raise ValueError("Could not find marketing version in project file")
    if not current_version_line:
        raise ValueError("Could not find current version in project file")

    current_marketing_version = (
        marketing_version_line[0].split("=")[1].strip().strip(";")
    )
    current_version = current_version_line[0].split("=")[1].strip().strip(";")

    return current_marketing_version, current_version


def get_marketing_version():
    git_tag = (
        subprocess.check_output(["git", "describe", "--tags"]).decode("utf-8").strip()
    )
    return git_tag.strip("v")


def get_build_version():
    date_str = datetime.now().strftime("%Y%m%d")
    git_commit = (
        subprocess.check_output(["git", "rev-parse", "--short", "HEAD"])
        .decode("utf-8")
        .strip()
    )
    _, build_version = get_current_versions()
    patch_version = 0
    if build_version.startswith(f"{date_str}.{git_commit}"):
        patch_version = int(build_version.split(".")[-1]) + 1

    return f"{date_str}.{git_commit}.{patch_version}"


def bump_versions():
    project_file_path = "./Roam.xcodeproj/project.pbxproj"

    current_marketing_version, current_build_version = get_current_versions()
    new_marketing_version, new_build_version = (
        get_marketing_version(),
        get_build_version(),
    )

    sed_cmd_marketing_version = f"sed -i '' 's/MARKETING_VERSION = {current_marketing_version};/MARKETING_VERSION = {new_marketing_version};/g' {project_file_path}"
    subprocess.run(sed_cmd_marketing_version, shell=True)

    sed_cmd_build_version = f"sed -i '' 's/CURRENT_PROJECT_VERSION = {current_build_version};/CURRENT_PROJECT_VERSION = {new_build_version};/g' {project_file_path}"
    subprocess.run(sed_cmd_build_version, shell=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Xcode exporting and publishing script"
    )

    parser.add_argument(
        "--archive",
        help="Build and archive the application",
        action="store_true",
    )

    parser.add_argument(
        "--publish",
        help="Publish the application to App Store Connect",
        action="store_true",
    )

    parser.add_argument(
        "--platform",
        help="Platform to build and publish",
        choices=["macOS", "iOS", "tvOS", "visionOS"],
        nargs="+",
    )

    parser.add_argument(
        "--github-actions",
        help="Render output for GitHub Actions",
        action="store_true",
    )

    args = parser.parse_args()

    bump_versions()

    if args.archive:
        for platform in args.platform:
            archive_application(platform, render_github_actions=parser.github_actions)

    if args.publish:
        for platform in args.platform:
            publish_to_app_store(platform, render_github_actions=parser.github_actions)
