#!/bin/bash
#
# Create a .deb package for DuckieTV


# Print an error message to stderr then exit
error(){
    echo "$PROGRAM:ERROR: $*" >&2
    exit 1
}


# Print an informational message
info(){
    echo "$PROGRAM:INFO: $*"
}


# Print a warning message to stderr
warning(){
    echo "$PROGRAM:WARNING: $*" >&2
}


# Ensure prerequisites are installed
check_prerequisites(){
    local missing=()

    for program in curl debtool; do
        hash "$program" &>/dev/null || missing+=("$program")
    done

    if (( ${#missing[@]} > 0 )); then
        error "Please install the following program(s) before continuing: ${missing[*]}"
        exit 1
    fi
}


# Determine the archive's platform architecture
get_architecture(){
    case $1 in
        *ia32*)
            echo 'i386'
            ;;
        *x64*)
            echo 'amd64'
            ;;
    esac
}


# Get link to latest DuckieTV release
get_download_url(){
    python3 <<-EOF
	import json, platform, re, requests

	def get_download_url(assets):
	    isX64 = re.search('x86_64|x86-64|Win64|x64|amd64|AMD64|WOW64|x64_64', platform.processor()) is not None
	    for asset in assets:
	        name = asset['name']
	        if name.find('Linux') > -1 and name.find('x64' if isX64 else 'ia32') > -1:
	            return asset['browser_download_url']

	URL = 'https://api.github.com/repos/SchizoDuckie/DuckieTV/releases'

	print(get_download_url(json.loads(requests.get(URL).text)[0]['assets']))
	EOF
}


PROGRAM=${0##*/}
SCRIPT_DIRECTORY=$(realpath "$(dirname "$0")")

info "Checking for prerequisites"
check_prerequisites

# enter the script directory
cd "$SCRIPT_DIRECTORY" || {
    error "Failed to cd into $SCRIPT_DIRECTORY"
}

URL=$(get_download_url)
ARCHIVE=$(sed 's:^.*/::' <<<"$URL")
VERSION=$(sed 's:/[^/]*$::;s:^.*/::' <<<"$URL")
ARCHITECTURE=$(get_architecture "$ARCHIVE")

# ensure essential variables are set before continuing
for var in URL ARCHIVE VERSION ARCHITECTURE; do
    [[ -n ${!var} ]] || {
        error "Unable to determine '$var'"
    }
done

# check whether archive already exists
if [[ -f $ARCHIVE ]]; then
    info "Archive '$ARCHIVE' already exists. Skipping download..."
else
    # download archive
    info "Downloading archive from '$URL'"
    curl -LOs "$URL" || {
        error "Failed to download '$URL'"
    }
fi

# determine destination directory to unpack into
DESTDIR=$(tar -tf "$ARCHIVE" | head -n1 | sed 's:/$::') || {
    error "Failed to determine destination directory for archive '$ARCHIVE'"
}

# check whether archive is already unpacked
if [[ -d $DESTDIR ]]; then
    info "Archive is already unpacked at '$DESTDIR'. Skipping unpack..."
else
    # unpack archive
    info "Unpacking archive '$ARCHIVE'"
    tar -xzf "$ARCHIVE" || {
        error "Failed to unpack archive '$ARCHIVE'"
    }
fi

# ensure directory exists
info "Ensuring directory './duckietv/opt/duckietv/' exists"
mkdir -p ./duckietv/opt/duckietv/ || {
    error "Failed to create directory './duckietv/opt/duckietv/'"
}

# copy files into package directory
info "Copying files into package directory"
for file in DuckieTV-bin icudtl.dat nw.pak; do
    cp "$DESTDIR/DuckieTV/$file" ./duckietv/opt/duckietv/ || {
        error "Failed to copy '$file' into './duckietv/opt/duckietv/'"
    }
done

# set file perms
info "Setting file permissions"
chmod 0644 ./duckietv/usr/share/{applications/duckietv.desktop,pixmaps/duckietv.png}
chmod 0755 ./duckietv/opt/duckietv/* ./duckietv/usr/bin/duckietv

# update architecture in control file
info "Updating architecture '$ARCHITECTURE' in package's control file"
sed -i "s/^\(Architecture:\) .*$/\1 $ARCHITECTURE/" ./duckietv/DEBIAN/control || {
    error "Failed to update architecture in ./duckietv/DEBIAN/control"
}

# update version string in control file
info "Updating version string '$VERSION' in package's control file"
sed -i "s/^\(Version:\) .*$/\1 $VERSION/" ./duckietv/DEBIAN/control || {
    error "Failed to update version string in ./duckietv/DEBIAN/control"
}

# build the .deb
info "Building .deb"
debtool --build --md5sums ./duckietv/ || {
    error "Failed to build .deb"
}

# remove unpacked archive
info "Cleaning up... Removing unpacked archive '$DESTDIR'"
rm -rf "$DESTDIR" || {
    warning "Failed to remove unpacked archive '$DESTDIR'"
}
