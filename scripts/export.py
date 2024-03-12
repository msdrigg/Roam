import re
import subprocess
from datetime import datetime
import argparse

# 1. Before running, make sure you create an API key from App Store Connect
#     (App Store Connect -> Users and Access -> Integrations -> App Store Connect API) and store the downloaded key in ~/.private_keys
# 2. Then set the following environment variables:
#     XCODE_API_KEY="API_KEY_ID"
#     XCODE_API_ISSUER="API_ISSUER_ID"
#     
#     Find both of these values in App Store Connect web after creating the API key


def bump_versions():
    project_file_path = "./Roam.xcodeproj/project.pbxproj"
    current_date = datetime.now().strftime("%Y.%m.%d").lstrip("0").replace(".0", ".")
    current_date_ints = list(map(int, current_date.split(".")))
    new_project_version = current_date_ints

    with open(project_file_path, "r") as file:
        project_contents = file.readlines()

    marketing_version_line = [
        line
        for line in project_contents
        if re.search(r"MARKETING_VERSION = \d+\.\d+;", line)
    ]
    if marketing_version_line:
        current_marketing_version = (
            marketing_version_line[0].split("=")[1].strip().strip(";")
        )
        major, minor = current_marketing_version.split(".")
        new_marketing_version = f"{major}.{int(minor)+1}"

        sed_cmd_marketing_version = f"sed -i '' 's/MARKETING_VERSION = {current_marketing_version};/MARKETING_VERSION = {new_marketing_version};/g' {project_file_path}"
        subprocess.run(sed_cmd_marketing_version, shell=True)

    current_version_line = [
        line
        for line in project_contents
        if re.search(r"CURRENT_PROJECT_VERSION = \d+\.\d+\.\d+", line)
    ]
    if current_version_line:
        current_project_version = (
            current_version_line[0].split("=")[1].strip().strip(";")
        )
        major, mid, minor = list(map(int, current_project_version.split(".")))

        new_project_version = [major, mid, minor + 1]
        for i in range(3):
            if new_project_version[i] > current_date_ints[i]:
                break
            elif new_project_version[i] < current_date_ints[i]:
                new_project_version = current_date_ints
                break

        new_project_version = ".".join(map(str, new_project_version))

        sed_cmd_project_version = f"sed -i '' 's/CURRENT_PROJECT_VERSION = {current_project_version};/CURRENT_PROJECT_VERSION = {new_project_version};/g' {project_file_path}"
        subprocess.run(sed_cmd_project_version, shell=True)


def archive_application(scheme: str, platform: str):
    project_path = "."
    archive_path = f"{project_path}/Archives/XCArchives/{platform}.xcarchive"
    print(f"Archiving application for platform {platform}")
    subprocess.run(
        f"xcodebuild archive -project {project_path}/Roam.xcodeproj -scheme {scheme} -archivePath {archive_path} -destination 'generic/platform={platform}'",
        shell=True,
    )
    print(f"Archive succeeded for platform {platform}")


def publish_to_app_store(platform: str, extension: str):
    print(f"Publishing for platform {platform} with extension {extension}")
    subprocess.run(
        f"xcodebuild -exportArchive -archivePath ./Archives/XCArchives/{platform}.xcarchive -exportPath ./Archives/Exports/{platform} -exportOptionsPlist ./Scripts/exportOptions.plist",
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Xcode project version bump and archiving script."
    )
    parser.add_argument(
        "--bump-versions",
        action="store_true",
        help="Bump the project version before archiving",
    )
    args = parser.parse_args()

    if args.bump_versions:
        bump_versions()

    archive_application("Roam", "macOS")
    archive_application("Roam", "iOS")
    archive_application("Roam", "visionOS")

    publish_to_app_store("iOS", "ipa")
    publish_to_app_store("visionOS", "ipa")
    publish_to_app_store("macOS", "pkg")
