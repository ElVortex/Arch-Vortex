#!/usr/bin/env bash
#github-action genshdoc
#
# @file scripts

package_list () {
  packages=''
  while read line
    do
      packages="$packages $line"
      if [[ ${INSTALL_TYPE} == 'FULL' ]]; then
        packages=`echo $packages | sed 's/ \-\-END OF MINIMAL INSTALL\-\- / /g'`
      elif [[ ${INSTALL_TYPE} == 'MINIMAL' ]]; then
        packages=`echo $packages | sed 's/ \-\-END OF MINIMAL INSTALL.*/ /g'`
      fi
    done < $1
}
