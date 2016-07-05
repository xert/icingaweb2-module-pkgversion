#!/bin/sh

PKG_PATH=/usr/sbin/pkg

PACKAGE_NAME=
PACKAGE_VERSION=
PACKAGE_SIZE=
PACKAGE_INSTALLED=
PACKAGE_INFORMATIONS=
PACKAGE_REPOSITORY_VERSION=

usage() {
  echo "This plugin tests version of given package"
  echo
  echo "Usage:"
  echo "$0 -p <pkg-name> [-w MINVERSION] [-c MINVERSION] [-ar]"
  echo
  echo "Options:"
  echo " -h, --help"
  echo "    Print detailed help screen"
  echo " -p, --package"
  echo "    Package name for pkg query -x (regex format)"
  echo " -w, --warning MINVERSION"
  echo "    Exit with WARNING status if package version is lower than MINVERSION"
  echo " -c, --critical MINVERSION"
  echo "    Exit with CRITICAL status if package version is lower than MINVERSION"
  echo " -a, --audit"
  echo "    Exit with CRITICAL status if package version has known vulnerabilities by pkg audit"
  echo " -r, --repo"
  echo "    Exit with WARNING status if newer version of the package exist in any of configured repositories"
  echo
  exit 3
}

ok() {
  echo -n OK - $@
  performance
  package_informations
  exit 0
}

warning() {
  echo -n WARNING - $@
  performance
  package_informations
  exit 1
}

critical() {
  echo -n CRITICAL - $@
  performance
  package_informations
  exit 2
}

unknown() {
  echo UNKNOWN - $@
  exit 3
}

performance() {
  if [ -z "$PACKAGE_VERSION" ]; then
    echo
    return
  fi

  echo "|version=$PACKAGE_VERSION size=$PACKAGE_SIZE updated=$PACKAGE_INSTALLED repository=$PACKAGE_REPOSITORY_VERSION"
}

package_informations() {
  if [ -n "$PACKAGE_INFORMATIONS" ]; then
    echo $PACKAGE_INFORMATIONS
  fi
}

# processes performance data format %n,%v,%sb,%t
# %n - package name
# %v - package version
# %sb - package size in bytes
# %t - timestamp of package installation
process_performance() {
  OLD_IFS=$IFS
  IFS=","
  set -- $1

  PACKAGE_NAME=$1
  PACKAGE_VERSION=$2
  PACKAGE_SIZE=$3
  PACKAGE_INSTALLED=$4

  IFS=$OLD_IFS
}

# returns 0 if version $1 is older than version $2, otherwise returns 1
older() {
  if [ -z "$1" -o -z "$2" ]; then
     return 1
  fi

  if [ `$PKG_PATH version -t $1 $2` = "<" ]; then
    return 0
  fi

  return 1
}

# PKGNG check
if [ ! -x $PKG_PATH ]; then
  unknown Program $PKG_PATH not found
fi

package=
warning=
critical=
audit=0
repo=0
while [ "$1" != "" ]; do
    case $1 in
        -p | --package )        shift
                                package=$1
                                ;;
        -w | --warning )        shift
				warning=$1
                                ;;
        -c | --critical )       shift
				critical=$1
                                ;;
        -a | --audit )          audit=1
                                ;;
        -r | --repo )           repo=1
                                ;;
        * )                     usage
				;;
    esac
    shift
done

if [ -z "$package" ]; then
  usage
fi

if [ "$warning" = "$critical" -a -n "$warning" ]; then
  unknown WARNING and CRITICAL versions are equal \($warning\)
fi

if older "$warning" "$critical"; then
  unknown WARNING value $warning can not be older version than CRITICAL $critical
fi

results=`pkg query -x "%n,%v,%sb,%t" "^${package}$"`
count=`echo $results | /usr/bin/wc -w`
if [ $count -eq 0 ]; then
  critical Package $package not found
fi
if [ $count -gt 1 ]; then
  unknown More than one package matching \"$package\" found \(total $count\)
fi

process_performance $results $repo_version
PACKAGE_REPOSITORY_VERSION=`$PKG_PATH search -S name -Q version -e $PACKAGE_NAME | grep Version | awk '{print $3}'`

if older $PACKAGE_VERSION "$critical"; then
  critical $PACKAGE_NAME version $PACKAGE_VERSION is older than $critical
fi

if [ $audit -eq 1 ]; then
  vulnerabilities=`$PKG_PATH audit -Ff /tmp/pkg_check_audit.tmp $PACKAGE_NAME-$PACKAGE_VERSION`
  if [ $? -eq 1 ]; then
    PACKAGE_INFORMATIONS="$vulnerabilities"
    critical $PACKAGE_NAME has known vulnerabilities
  fi
fi

if older $PACKAGE_VERSION "$warning"; then
  warning $PACKAGE_NAME version $PACKAGE_VERSION is older than $warning
fi

if [ $repo -eq 1 ]; then
  if older $PACKAGE_VERSION $PACKAGE_REPOSITORY_VERSION; then
    warning $PACKAGE_NAME version $PACKAGE_VERSION is older than repository version $PACKAGE_REPOSITORY_VERSION
  fi
fi

ok $PACKAGE_NAME version is $PACKAGE_VERSION
