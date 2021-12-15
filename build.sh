#!/bin/bash

BASE_DIR=$(pwd)

VERSION=$1
if [ -z "$VERSION" ]; then
	echo "No version was specified."
	exit 1
fi

REMOTE_REPOSITORY_URL=$2

if [ -z "$REMOTE_REPOSITORY_URL" ]; then
	echo "No remote repository URL was specified."
fi

REMOTE_REPOSITORY_ID=$3

if [ -z "$REMOTE_REPOSITORY_ID" ]; then
	echo "No remote repository ID was specified."
fi

BUILD_DIR=$BASE_DIR/target
ES_DIR=$BUILD_DIR/elasticsearch-${VERSION}

if [[ "${VERSION}" == 6* ]]; then
	ES_BINARY_FILE=elasticsearch-${VERSION}
else
	ES_BINARY_FILE=elasticsearch-${VERSION}-windows-x86_64
fi

ES_BINARY_URL=https://artifacts.elastic.co/downloads/elasticsearch/${ES_BINARY_FILE}.zip
ES_SOURCE_URL=https://github.com/elastic/elasticsearch/archive/v${VERSION}.zip
REPO_DIR=$BUILD_DIR/repository

mkdir -p "$BUILD_DIR"
rm -rf "$ES_DIR" "$REPO_DIR"
mkdir -p "$ES_DIR" "$REPO_DIR"

cd "$BUILD_DIR" || exit

# Download source zip
if [ ! -f "${BUILD_DIR}/v${VERSION}.zip" ]; then
	curl -sSL "$ES_SOURCE_URL" -o "v${VERSION}.zip"
fi

if [ ! -f "${BUILD_DIR}/v${VERSION}.zip" ]; then
	echo "Failed to download v${VERSION}.zip."
	exit 1
fi

unzip -n v"${VERSION}".zip >/dev/null && echo "Unzipped Github repository content"

# Download binary zip
if [ ! -f "${BUILD_DIR}/${ES_BINARY_FILE}.zip" ]; then
	curl -sSOJL "$ES_BINARY_URL"
fi

if [ ! -f "${BUILD_DIR}/${ES_BINARY_FILE}.zip" ]; then
	echo "Failed to download ${ES_BINARY_FILE}.zip."
	exit 1
fi

unzip -n "${ES_BINARY_FILE}".zip >/dev/null && echo "Unzipped Elasticsearch binary"

rm -r "$ES_DIR"/x-pack

function generate_pom() {

	MODULE_DIR=$1
	MODULE_NAME=$2
	MODULE_TYPE=$3

	pushd "${ES_DIR}/$MODULE_TYPE/${MODULE_DIR}" >/dev/null || exit

	echo ""
	echo "Generating pom for '${MODULE_NAME}' with type '${MODULE_TYPE}' in dir ${ES_DIR}/$MODULE_TYPE/${MODULE_DIR}"
	echo ""

	JAR_FILE=$(/bin/ls "${MODULE_NAME}"*.jar)
	mv "$JAR_FILE" "${JAR_FILE/-client/}" 2>/dev/null
	MODULE_VERSION=$(/bin/ls "${MODULE_NAME}"*.jar | sed -e "s/^${MODULE_NAME}-\(.*\).jar/\1/")
	POM_FILE="${MODULE_NAME}-${MODULE_VERSION}.pom"
	GROUP_ID="org.codelibs.elasticsearch.${MODULE_TYPE%s}"

	echo " Assembling '$POM_FILE':"

	echo "   Group ID:    ${GROUP_ID}"
	echo "   Artifact ID: ${MODULE_NAME}"
	echo "   Version:     ${MODULE_VERSION}"

	{
		echo '<?xml version="1.0" encoding="UTF-8"?>'
		echo '<project xmlns="http://maven.apache.org/POM/4.0.0" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
		echo '  <modelVersion>4.0.0</modelVersion>'
		echo '  <groupId>'"${GROUP_ID}"'</groupId>'
		echo '  <artifactId>'"${MODULE_NAME}"'</artifactId>'
		echo '  <version>'"${MODULE_VERSION}"'</version>'
		echo '  <dependencies>'
	} >>"${POM_FILE}"

	echo ""

	for JAR_FILE in $(/bin/ls -- *.jar | grep -v ^"$MODULE_NAME"); do

		echo "    Processing dependency '$JAR_FILE':"

		# shellcheck disable=SC2016
		sed -i 's/project(.:server.)/"org.elasticsearch:elasticsearch:${version}"/g' build.gradle
		# shellcheck disable=SC2016
		sed -i 's/project(.:client:rest.)/"org.elasticsearch.client:elasticsearch-rest-client:${version}"/g' build.gradle
		# shellcheck disable=SC2016
		sed -i 's/project(.:libs:elasticsearch-ssl-config.)/"org.elasticsearch:elasticsearch-ssl-config:${version}"/g' build.gradle

		# shellcheck disable=SC2001
		JAR_NAME=$(echo "$JAR_FILE" | sed -e "s/\(.*\)-[0-9].[0-9].*.jar/\1/g")
		# shellcheck disable=SC2001
		JAR_VERSION=$(echo "$JAR_FILE" | sed -e "s/.*-\([0-9].[0-9].*\).jar/\1/g")

		CLASSIFIER=$(grep ":$JAR_NAME:.*:" build.gradle | sed -e "s/.*\(compile\|api\|implementation\).*['\"].*:$JAR_NAME:.*:\(.*\)['\"]/\2/")
		if [ -n "$CLASSIFIER" ]; then
			# shellcheck disable=SC2001
			JAR_VERSION=$(echo "$JAR_VERSION" | sed -e "s/\-$CLASSIFIER$//")
		fi

		GROUP_ID=$(grep ":$JAR_NAME:" build.gradle | sed -e "s/.*\(compile\|api\|implementation\).*['\"]\(.*\):$JAR_NAME:.*/\2/")

		if [ "$JAR_NAME" = "elasticsearch-scripting-painless-spi" ]; then
			GROUP_ID="org.codelibs.elasticsearch.module"
			JAR_NAME="scripting-painless-spi"
		elif [ "$JAR_NAME" = "elasticsearch-grok" ]; then
			GROUP_ID="org.codelibs.elasticsearch.lib"
			JAR_NAME="grok"
		elif [ "$JAR_NAME" = "elasticsearch-ssl-config" ]; then
			GROUP_ID="org.codelibs.elasticsearch.lib"
			JAR_NAME="ssl-config"
		elif [ "$JAR_NAME" = "elasticsearch-dissect" ]; then
			GROUP_ID="org.codelibs.elasticsearch.lib"
			JAR_NAME="dissect"
		elif [ "$JAR_NAME" = "elasticsearch-rest-client" ]; then
			GROUP_ID="org.elasticsearch.client"
			JAR_NAME="elasticsearch-rest-client"
		elif [ "$JAR_NAME" = "reindex-client" ]; then
			GROUP_ID="org.elasticsearch.plugin"
			JAR_NAME="reindex-client"
		elif [ -z "$GROUP_ID" ]; then
			POMXML_FILE=$(jar tf "$JAR_FILE" | grep pom.xml)
			jar xf "$JAR_FILE" "$POMXML_FILE"
			GROUP_ID=$(xmllint <"$POMXML_FILE" --format - | sed -e "s/<project [^>]*>/<project>/" | xmllint --xpath "/project/groupId/text()" - 2>/dev/null)
			if [ -z "$GROUP_ID" ]; then
				GROUP_ID=$(xmllint <"$POMXML_FILE" --format - | sed -e "s/<project [^>]*>/<project>/" | xmllint --xpath "/project/parent/groupId/text()" - 2>/dev/null)
			fi
		fi

		if [ -z "$GROUP_ID" ] || [ -z "$JAR_VERSION" ]; then
			echo "[$JAR_NAME] groupId or version is empty."
			exit 1
		fi

		echo "      Group ID:     ${GROUP_ID}"
		echo "      Artifact ID:  ${JAR_NAME}"
		echo "      Version:      ${JAR_VERSION}"

		if [ -n "$CLASSIFIER" ]; then
			echo "     Classifier:   ${CLASSIFIER}"
		fi

		{
			echo '    <dependency>'
			echo '      <groupId>'"$GROUP_ID"'</groupId>'
			echo '      <artifactId>'"$JAR_NAME"'</artifactId>'
			echo '      <version>'"$JAR_VERSION"'</version>'
			if [ -n "$CLASSIFIER" ]; then
				echo '      <classifier>'"$CLASSIFIER"'</classifier>'
			fi
			echo '    </dependency>'
		} >>"${POM_FILE}"

	done

	if [ "${MODULE_NAME}" = "lz4" ]; then

		{
			echo '    <dependency>'
			echo '      <groupId>org.lz4</groupId>'
			echo '      <artifactId>lz4-java</artifactId>'
			echo '      <version>1.8.0</version>'
			echo '    </dependency>'
		} >>"${POM_FILE}"

	fi

	{
		echo '  </dependencies>'
		echo '  <inceptionYear>2009</inceptionYear>'
		echo '  <licenses>'
		echo '    <license>'
		echo '      <name>Elastic License 2.0</name>'
		echo '      <url>https://raw.githubusercontent.com/elastic/elasticsearch/'"v${VERSION}"'/licenses/ELASTIC-LICENSE-2.0.txt</url>'
		echo '      <distribution>repo</distribution>'
		echo '    </license>'
		echo '  </licenses>'
		echo '  <developers>'
		echo '    <developer>'
		echo '      <name>Elastic</name>'
		echo '      <url>http://www.elastic.co</url>'
		echo '    </developer>'
		echo '    <developer>'
		echo '      <name>CodeLibs</name>'
		echo '      <url>http://www.codelibs.org/</url>'
		echo '    </developer>'
		echo '  </developers>'
		echo '  <name>'"$MODULE_NAME"'</name>'
		echo '  <description>Elasticsearch module: '"$MODULE_NAME"'</description>'
		echo '  <url>https://github.com/codelibs/elasticsearch-module</url>'
		echo '  <scm>'
		echo '    <url>git@github.com:codelibs/elasticsearch-module.git</url>'
		echo '  </scm>'
		echo '</project>'
	} >>"${POM_FILE}"

	echo ""

	popd >/dev/null || return

}

function generate_source() {

	MODULE_DIR=$1
	MODULE_NAME=$2
	MODULE_TYPE=$3

	pushd "${ES_DIR}/$MODULE_TYPE/${MODULE_DIR}/src/main/java" >/dev/null || return
	SOURCE_FILE="${MODULE_NAME}-${MODULE_VERSION}-sources.jar"

	echo "Generating source file '$SOURCE_FILE'"
	jar cvf ../../../"$SOURCE_FILE" ./* >/dev/null

	popd >/dev/null || return

}

function deploy_files() {

	MODULE_DIR=$1
	MODULE_NAME=$2
	MODULE_TYPE=$3

	pushd "${ES_DIR}/$MODULE_TYPE/${MODULE_DIR}" >/dev/null || return
	POM_FILE="${MODULE_NAME}-${MODULE_VERSION}.pom"
	BINARY_FILE="${MODULE_NAME}-${MODULE_VERSION}.jar"
	SOURCE_FILE="${MODULE_NAME}-${MODULE_VERSION}-sources.jar"

	if [ -n "${REMOTE_REPOSITORY_URL}" ] && [ -n "${REMOTE_REPOSITORY_ID}" ]; then
		echo "Deploying $POM_FILE to remote repository"
		mvn deploy:deploy-file -Durl="${REMOTE_REPOSITORY_URL}" -DrepositoryId="${REMOTE_REPOSITORY_ID}" -Dfile="$BINARY_FILE" -Dsource="$SOURCE_FILE" -DpomFile="$POM_FILE"
	else
		echo "Deploying $POM_FILE to a local repository"
		mvn deploy:deploy-file -Dgpg.skip=false -Durl=file:"$REPO_DIR" -Dfile="$BINARY_FILE" -Dsources="$SOURCE_FILE" -DpomFile="$POM_FILE"
	fi

	popd >/dev/null || return

}

function generate_lang_painless_spi() {

	MODULE_DIR="lang-painless/spi"
	MODULE_NAME="scripting-painless-spi"
	MODULE_TYPE="modules"
	JAR_FILE=$(/bin/ls "$ES_DIR"/"$MODULE_TYPE"/lang-painless/spi/elasticsearch-scripting-painless-spi-*.jar 2>/dev/null)

	if [ -z "$JAR_FILE" ]; then
		return
	fi

	# shellcheck disable=SC2001
	NEW_JAR_FILE=$(echo "$JAR_FILE" | sed -e "s/elasticsearch-scripting-painless-spi-/scripting-painless-spi-/")
	cp "$JAR_FILE" "$NEW_JAR_FILE"

	generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE

}

function generate_plugin_classloader() {

	MODULE_DIR="plugin-classloader"
	MODULE_NAME="plugin-classloader"
	MODULE_TYPE="libs"

	JAR_FILE=$(/bin/ls "$ES_DIR"/lib/*plugin-classloader-*.jar 2>/dev/null)

	if [ -z "$JAR_FILE" ]; then
		return
	fi

	cp "$JAR_FILE" "$ES_DIR/$MODULE_TYPE/$MODULE_NAME/$(basename "$JAR_FILE" | sed -e "s/elasticsearch-plugin-classloader-/plugin-classloader-/")"

	generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE

}

function generate_lz4() {

	MODULE_DIR="lz4"
	MODULE_NAME="lz4"
	MODULE_TYPE="libs"
	JAR_FILE=$(/bin/ls "$ES_DIR"/lib/*-lz4-*.jar 2>/dev/null)

	if [ -z "$JAR_FILE" ]; then
		return
	fi

	cp "$JAR_FILE" "$ES_DIR/$MODULE_TYPE/$MODULE_NAME/$(basename "$JAR_FILE" | sed -e "s/elasticsearch-lz4-/lz4-/")"

	generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE

}

function generate_grok() {
	MODULE_DIR="grok"
	MODULE_NAME="grok"
	MODULE_TYPE="libs"
	JAR_FILE=$(/bin/ls "$ES_DIR"/modules/ingest-common/elasticsearch-grok-*.jar 2>/dev/null)

	if [ -z "$JAR_FILE" ]; then
		return
	fi

	cp "$JAR_FILE" "$ES_DIR/$MODULE_TYPE/$MODULE_NAME/$(basename "$JAR_FILE" | sed -e "s/elasticsearch-grok-/grok-/")"

	generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE

}

function generate_ssl_config() {

	MODULE_DIR="ssl-config"
	MODULE_NAME="ssl-config"
	MODULE_TYPE="libs"

	JAR_FILE=$(/bin/ls "$ES_DIR"/modules/reindex/elasticsearch-ssl-config-*.jar 2>/dev/null)

	if [ -z "$JAR_FILE" ]; then
		return
	fi

	cp "$JAR_FILE" "$ES_DIR/$MODULE_TYPE/$MODULE_NAME/$(basename "$JAR_FILE" | sed -e "s/elasticsearch-ssl-config-/ssl-config-/")"

	generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE

}

function generate_dissect() {

	MODULE_DIR="dissect"
	MODULE_NAME="dissect"
	MODULE_TYPE="libs"

	JAR_FILE=$(/bin/ls "$ES_DIR"/modules/ingest-common/elasticsearch-dissect-*.jar 2>/dev/null)

	if [ -z "$JAR_FILE" ]; then
		return
	fi

	cp "$JAR_FILE" "$ES_DIR/$MODULE_TYPE/$MODULE_NAME/$(basename "$JAR_FILE" | sed -e "s/elasticsearch-dissect-/dissect-/")"

	generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
	deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE

}

generate_lang_painless_spi
generate_plugin_classloader
generate_lz4
generate_grok
generate_ssl_config
generate_dissect

MODULE_NAMES=$(find "${ES_DIR}/modules/" -mindepth 2 -maxdepth 2 -type f -name build.gradle | sed -e "s,.*/\([^/]*\)/build.gradle,\1,")

for MODULE_NAME in $MODULE_NAMES; do

	if ! /bin/ls "${ES_DIR}"/modules/"${MODULE_NAME}"/*.jar >/dev/null 2>&1; then
		continue
	fi

	generate_pom "$MODULE_NAME" "$MODULE_NAME" modules
	generate_source "$MODULE_NAME" "$MODULE_NAME" modules
	deploy_files "$MODULE_NAME" "$MODULE_NAME" modules

done

pushd "$REPO_DIR"/org/codelibs/elasticsearch >/dev/null || exit

echo ""
echo "List of generated poms:"
find ./* -type f | grep pom$
