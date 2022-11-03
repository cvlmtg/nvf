# (N)ode (V)ersion manager for the (F)ish shell
# =============================================
#
# This script started as a simple conversion to fish of nave,
# written by Isaac Z. Schlueter (https://github.com/isaacs/nave)
#
# Some ideas and/or code have been taken from nvm, written by
# Tim Caswell (https://github.com/creationix/nvm)
#
# Some ideas might have been taken from rvm, rbenv and others.
#
# All the bugs are my own.
#
# INSTALLATION
# ============
#
# Place this script inside ~/.config/fish/functions, create the
# directory ~/.nvf and then add this line to ~/.config/fish/config.fish
#
# if test -d ~/.nvf; nvf init; end

function nvf
    set -l NVF_DIR  $HOME/.nvf
    set -l NVF_SRC  $NVF_DIR/sources
    set -l NVF_ROOT $NVF_DIR/installed

    function __ensure_dir
        if test -d $argv[1]
            return 0
        end
        mkdir -p $argv[1]
    end

    function __get
        curl -H "'user-agent:nvf-"(curl --version | head -n1)"'" $argv
    end

    function __version --no-scope-shadowing
        # translates the version supplied on the command line into
        # an actual version (e.g. 'stable' or just '0.10' to select
        # the lastest version in the 0.10.xx releases
        set -l _version (echo $argv[1] | sed 's/^v//')

        switch $_version
            case latest
                __nvf_latest
            case stable
                __nvf_stable
            case '?*.?*.?*'
                echo $_version
            case '?*.?*'
                __version_family $_version
            case '*'
                return 1
        end
    end

    function __get_versions --no-scope-shadowing
      __get -s https://nodejs.org/dist/
    end

    function __sort_versions
        # extracts node versions according to patterns and sorts them
        set -l pattern

        if test (count $argv) -eq 0
            set pattern '[0-9]+\.[0-9]+\.[0-9]+'
        else
            set pattern $argv[1]
        end

        egrep -o $pattern | sort -u -k 1,1n -k 2,2n -k 3,3n -t .
    end

    function __version_family
        set -l family $argv[1]

        __get_versions \
            | __sort_versions $family'\.[0-9]+' \
            | tail -n1
    end

    function __print_versions --no-scope-shadowing
        set -l padded_version
        set -l counter 0

        while read -l _version
            if test -d $NVF_ROOT/node-$_version
                set padded_version (printf '%s%-10s%s' \
                    (set_color $fish_color_command[1]) \
                    $_version \
                    (set_color $fish_color_normal[1]))
            else
                set padded_version (printf '%-10s' $_version)
            end

            if test $counter -ne 6
                set counter (math $counter+1)
                echo -ne $padded_version' '
            else
                echo -e $padded_version
                set counter 0
            end
        end

        echo ''
        if test $counter -ne 0
            echo ''
        end
    end

    function __is_installed --no-scope-shadowing
        test -x $NVF_ROOT/node-$argv[1]/bin/node
    end

    function __verify_checksum --no-scope-shadowing
        set -l remote $argv[1]
        set -l url (dirname $remote)
        set -l archive (basename $remote)

        set -l rsum (curl -s $url/SHASUMS256.txt \
            | grep $archive \
            | awk '{print $1}')

        if test -z "$rsum"
            echo Checksum not found for $archive
            return 1
        else
            set -l lsum (shasum -a 256 $NVF_SRC/$archive | awk '{print $1}')
            if test $rsum != $lsum
                echo Checksums do not match
                return 1
            end
        end

        return 0
    end

    function __get_file --no-scope-shadowing
        set -l remote $argv[1]
        set -l archive (basename $remote)

        echo Downloading $remote

        if test -f $NVF_SRC/$archive
            return 0
        end

        __get -L -f --progress-bar $remote -o $NVF_SRC/$archive
    end

    function __get_binary_version --no-scope-shadowing
        set -l _version $argv[1]
        set -l arch
        set -l os

        switch (uname -s)
            case Darwin
                set os darwin
            case Linux
                set os linux
            case '*'
                return 1
        end

        switch (uname -m)
            case arm64
                set arch arm64
            case x86_64
                set arch x64
            case '*'
                set arch x86
        end

        echo node-v$_version-$os-$arch.tar.gz
    end

    function __install_binary --no-scope-shadowing
        set -l destination $argv[3]
        set -l remote $argv[2]
        set -l _version $argv[1]

        set -l archive (__get_binary_version $_version)
        set -l local $NVF_SRC/$archive

        # get the file and directly unpack it into ~/.nvf/installed/
        __get_file $remote/$archive
        and __verify_checksum $remote/$archive
        and tar xzf $local -C $destination --strip-components=1
        or begin
            echo node installation failed.
            rm -f $local
            return 1
        end
    end

    function __clear_env --no-scope-shadowing
        which node > /dev/null
        or return

        set -l node_version (node --version | sed 's/^v//')
        set -l node_version node-$node_version
        set -l man $NVF_ROOT/$node_version/share/man
        set -l bin $NVF_ROOT/$node_version/bin

        if contains $man $MANPATH
            set -l index (contains -i $man $MANPATH)
            set -e MANPATH[$index]
        end

        if contains $bin $PATH
            set -l index (contains -i $bin $PATH)
            set -e PATH[$index]
        end
    end

    function __setup_env
        set -l man $argv[1]/share/man
        set -l bin $argv[1]/bin

        if not contains $man $MANPATH
            if test -z "$MANPATH"
              set -g MANPATH :$man
            else
              set -g MANPATH $man "$MANPATH"
            end
        end

        if not contains $bin $PATH
            set PATH $bin $PATH
        end
    end

    function __nvf_local --no-scope-shadowing
        if test -z "$argv[1]" -o "$argv[1]" = 'system'
            echo Using system node
            __clear_env
            return
        end

        set -l _version (__version $argv[1])
        set -l bin $NVF_ROOT/node-$_version/bin

        if contains $bin $PATH
            if test $quiet -eq 0
                echo Already using node $_version
            end
            return
        end

        which node > /dev/null
        and begin
            set -l node_version (node --version)
            if test v$_version = $node_version
                if test $quiet -eq 0
                    echo Already using node $_version
                end
                return
            end
        end

        if not __is_installed $_version
            echo node $_version is not installed
            return 1
        end

        __clear_env
        __setup_env $NVF_ROOT/node-$_version

        if test $quiet -ne 2
            echo Using node $_version
        end
    end

    function __nvf_global --no-scope-shadowing
        if test $argv[1] = 'system'
            echo Using system node
            rm $NVF_DIR/default
            __clear_env
            return
        end

        __nvf_local $argv
        # save the selected version
        set -l _version (__version $argv[1])
        and echo node-$_version > $NVF_DIR/default
    end

    function __nvf_clean --no-scope-shadowing
        if test (count $argv) -eq 0
            rm -rf $NVF_SRC/*
        else
            set -l _version (__version $argv[1])
            rm -rf $NVF_SRC/node-?$_version*
        end
    end

    function __nvf_install --no-scope-shadowing
        set -l _version (__version $argv[1])

        if __is_installed $_version
            echo node $_version already installed
        else
            set -l destination $NVF_ROOT/node-$_version
            set -l remote

            __ensure_dir $destination
            and begin
                set remote https://nodejs.org/dist/v$_version
                __install_binary $_version $remote $destination
                and echo node $_version succesfully installed
                or rm -rf $destination
            end
            or echo Cannot create $destination
        end
    end

    function __nvf_uninstall --no-scope-shadowing
        set -l _version (__version $argv[1])

        if not __is_installed $_version
            echo node $_version is not installed
            return 1
        end

        which node > /dev/null
        and begin
            set -l dir $NVF_ROOT/node-$_version

            # if we are using a "local" version, switch to the "global"
            # version. if we are using a "global" version, switch
            # to the system version and erase ~/.nvf/default
            # if we are using a system node, do nothing

            if contains $dir $PATH
                set -l global (cat $NVF_DIR/default)

                if test node-$_version = $global
                    __nvf_global system
                else
                    set -l conf (echo $global | tr '-' '\n')
                    __nvf_local $conf[2]
                end
            end
        end

        rm -rf $NVF_ROOT/node-$_version
        echo Uninstalled node $_version
    end

    function __nvf_latest --no-scope-shadowing
        __get_versions | __sort_versions  | tail -n1
    end

    function __nvf_stable --no-scope-shadowing
        set -l pattern '[0-9]*[02468]\.[0-9]+\.[0-9]+'

        __get_versions | __sort_versions $pattern | tail -n1
    end

    function __nvf_ls --no-scope-shadowing
        set -l pattern '[a-z]+-[0-9]+\.[0-9]+\.[0-9]+'

        echo installed:
        ls $NVF_ROOT | __sort_versions $pattern | __print_versions
    end

    function __nvf_ls_remote --no-scope-shadowing
        echo remote:
        __get_versions | __sort_versions | __print_versions
    end

    function __nvf_go_up
        set -l dir $argv[1]
        set -l top $argv[2]

        while test $dir != $top
            set dir (dirname $dir)

            if test -f $dir/.nvf
                echo $dir/.nvf
                return
            end
        end

        echo ''
    end

    function __nvf_find_dotfile --no-scope-shadowing
        if test -f $PWD/.nvf
            echo $PWD/.nvf
            return
        end

        if test -z "$__nvf_cached_pwd"
            set -gx __nvf_cached_pwd /
        end

        # check if we are in a subdir of a cached
        # directory where we found our dotfile
        set -l idx 0

        for tmp in $__nvf_cached_dirs
            set idx (math $idx + 1)

            switch $PWD
                case $tmp/'*'
                    if test ! -f $tmp/.nvf
                        # update the cache!
                        set -e __nvf_cached_dirs[$idx]
                    else
                        echo $tmp/.nvf
                        return
                    end
            end
        end

        # look for our dotfile up to the last 'cd' where we
        # did not find any. this should avoid us to hit the
        # disk too many times
        set -l found ''

        switch $PWD
            case $__nvf_cached_pwd/'*'
                set found (__nvf_go_up $PWD, $__nvf_cached_pwd)
            case $__nvf_cached_pwd
                # NOOP
            case '*'
                set found (__nvf_go_up $PWD, /)
                set __nvf_cached_pwd $PWD
        end

        if test -n $found
            set -U __nvf_cached_dirs $__nvf_cached_dirs (dirname $found)
            echo $found
            return
        end

        echo $NVF_DIR/default
    end

    function __nvf_auto_change --no-scope-shadowing
        set -l name (__nvf_find_dotfile)
        set -l conf 'system'

        if test -e $name
          set conf (cat $name | tr '-' '\n')
        end

        set quiet $argv[1]
        __nvf_local $conf[2]
    end

    function __nvf_help
        echo "
Usage: nvf <command>

Commands:

install <version>    Install the version specified (e.g. 0.10.22)
global <version>     Use <version> for the current and future sessions
local <version>      Use <version> for the current session only
auto                 Change version based on the content of the .nvf
                     file found in the current directory or in one of
                     the parent directories. If no such file is found
                     then the default is used
clean <version>      Delete the source code for <version>
uninstall <version>  Delete <version>
ls                   List versions currently installed
ls-remote            List remote node versions
ls-all               List remote and local node versions
latest               Show the most recent version
stable               Show the most recent stable version
help                 Output help information

<version> can be:
    'stable' to get the latest stable version.
    'latest' to get the latest distribution.
    'system' to use the system-wide node.

'system' is only available to the 'local' and 'global' commands.

to uninstall nvf just delete ~/.nvf and ~/.config/fish/functions/nvf.fish
"
    end

    if test (count $argv) -eq 0
        __nvf_help
        return
    end

    __ensure_dir $NVF_ROOT
    __ensure_dir $NVF_SRC

    set -l quiet 0
    set -l args
    set -l arg

    while test (count $argv) -ne 0
        set arg $argv[1]

        switch $arg
            case -q --quiet
                set quiet 1
            case '*'
                set args $args $arg
        end
        set -e argv[1]
    end

    set -l command $args[1]
    set -e args[1]

    switch $command
        case init
            __nvf_auto_change 2
        case ls-all
            __nvf_ls_remote
            __nvf_ls
        case ls-remote
            __nvf_ls_remote
        case ls
            __nvf_ls
        case latest
            __nvf_latest
        case stable
            __nvf_stable
        case local
            __nvf_local $args
        case global
            __nvf_global $args
        case uninstall
            __nvf_uninstall $args
        case install
            __nvf_install $args
        case clean
            __nvf_clean $args
        case auto
            __nvf_auto_change 1
        case '*'
            __nvf_help
    end
end
