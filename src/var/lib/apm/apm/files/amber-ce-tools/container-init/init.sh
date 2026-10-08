#!/bin/bash 
# Set by the host initializer, not the Debian container's /etc/os-release.
if [ "${APM_HOST_NIXOS:-0}" = 1 ]; then
        set -e
fi

if [ "$IS_ACE_ENV" != "1" ];then
echo "ONLY RUN ME IN ACE"
exit
fi



        printf "ACE: Setting up sudo...\n"
        mkdir -p /etc/sudoers.d
        touch /etc/sudoers.d/sudoers
        # Do not check fqdn when doing sudo, it will not work anyways
        if ! grep -q 'Defaults !fqdn' /etc/sudoers.d/sudoers; then
                printf "Defaults !fqdn\n" >> /etc/sudoers.d/sudoers
        fi
        # Ensure passwordless sudo is set up for user
        if ! grep -q "\"${container_user_name}\" ALL = (root) NOPASSWD:ALL" /etc/sudoers.d/sudoers; then
                printf "\"%s\" ALL = (root) NOPASSWD:ALL\n" "${container_user_name}" >> /etc/sudoers.d/sudoers
        fi




printf "ACE: Setting up groups...\n"
# If not existing, ensure we have a group for our user.
if ! grep -q "^${container_user_name}:" /etc/group; then
        if ! groupadd --force --gid "${container_user_gid}" "${container_user_name}"; then
                # It may occur that we have users with unsupported user name (eg. on LDAP or AD)
                # So let's try and force the group creation this way.
                printf "%s:x:%s:\n" "${container_user_name}" "${container_user_gid}" >> /etc/group
        fi
fi

printf "ACE: Setting up users...\n"

# Setup kerberos integration with the host
if [ -d "/run/host/var/kerberos" ] &&
        [ -d "/etc/krb5.conf.d" ] &&
        [ ! -e "/etc/krb5.conf.d/kcm_default_ccache" ]; then

        cat << EOF > "/etc/krb5.conf.d/kcm_default_ccache"
# # To disable the KCM credential cache, comment out the following lines.
[libdefaults]
    default_ccache_name = KCM:
EOF
fi

# If we have sudo/wheel groups, let's add the user to them.
additional_groups=""
container_shell="${SHELL:-/bin/bash}"
if grep -q "^sudo" /etc/group; then
        additional_groups="sudo"
elif grep -q "^wheel" /etc/group; then
        additional_groups="wheel"
fi

# Let's add our user to the container. if the user already exists, enforce properties.
#
# In case of AD or LDAP usernames, it is possible we will have a backslach in the name.
# In that case grep would fail, so we replace the backslash with a point to make the regex work.
# shellcheck disable=SC1003
if ! grep -q "^$(printf '%s' "${container_user_name}" | tr '\\' '.'):" /etc/passwd &&
        ! grep -q "^.*:.*:${container_user_uid}:" /etc/passwd; then
        if ! useradd \
                --home-dir "${container_user_home}" \
                --no-create-home \
                --groups "${additional_groups}" \
                --shell "${container_shell}" \
                --uid "${container_user_uid}" \
                --gid "${container_user_gid}" \
                "${container_user_name}"; then

                printf "Warning: there was a problem setting up the user\n"
                printf "Warning: trying manual addition\n"
                printf "%s:x:%s:%s:%s:%s:%s\n" \
                        "${container_user_name}" "${container_user_uid}" \
                        "${container_user_gid}" "${container_user_name}" \
                        "${container_user_home}" "${container_shell}" >> /etc/passwd
                printf "%s::1::::::\n" "${container_user_name}" >> /etc/shadow
        fi
# Ensure we're not using the specified SHELL. Run it only once, so that future
# user's preferences are not overwritten at each start.
elif [ ! -e /etc/passwd.done ]; then
        # This situation is presented when podman or docker already creates the user
        # for us inside container. We should modify the user's prepopulated shadowfile
        # entry though as per user's active preferences.

        # If the user was there with a different username, get that username so
        # we can modify it
        if ! grep -q "^$(printf '%s' "${container_user_name}" | tr '\\' '.'):" /etc/passwd; then
                user_to_modify=$(getent passwd "${container_user_uid}" | cut -d: -f1)
        fi

        if ! usermod \
                --home "${container_user_home}" \
                --shell "${container_shell}" \
                --groups "${additional_groups}" \
                --uid "${container_user_uid}" \
                --gid "${container_user_gid}" \
                --login "${container_user_name}" \
                "${user_to_modify:-"${container_user_name}"}"; then

                printf "Warning: there was a problem setting up the user\n"
        fi
        touch /etc/passwd.done
fi
if [ "${APM_HOST_NIXOS:-0}" = 1 ] && [ ! -e /etc/passwd.done ]; then
        touch /etc/passwd.done
fi

# We generate a random password to initialize the entry for the user and root.
temporary_password="$(cat /proc/sys/kernel/random/uuid)"
printf "%s\n%s\n" "${temporary_password}" "${temporary_password}" | passwd root
printf "%s:%s" "${container_user_name}" "${temporary_password}" | chpasswd -e
# Delete password for root and user
printf "%s:" "root" | chpasswd -e
printf "%s:" "${container_user_name}" | chpasswd -e

mkdir -p /usr/share/fonts
mkdir -p /usr/share/icons
mkdir -p /usr/share/themes

## init host-spawn
rm -f /amber-ce-tools/bin-override/host-spawn
ln -sfv /amber-ce-tools/bin-override/host-spawn-$(uname -m) /amber-ce-tools/bin-override/host-spawn





exit 0
