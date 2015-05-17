function cd
    builtin cd $argv

    set -l last_status $status
    nvf auto

    return $last_status
end
