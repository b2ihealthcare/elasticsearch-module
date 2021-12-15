@Library('jenkins-shared-library') _

/**
* Job Parameters:
*	targetVersion - the version of Elasticsearch to generate artifacts from
*	remoteRepositoryURL - the remote maven repository URL
*	remoteRepositoryID - the remote maven repository ID
*	custom_maven_settings - custom maven settings
*
**/
try {

	slack.notifyBuild()

	node('docker') {

		stage('Checkout repository') {
			checkout scm
		}

		stage('Build') {

			sh 'rm -rf ${WORKSPACE}/target'
			sh 'mkdir ${WORKSPACE}/target'

			def esBinaryFileName

			if (targetVersion.startsWith("6")) {
				esBinaryFileName = "elasticsearch-${targetVersion}"
			} else {
				esBinaryFileName = "elasticsearch-${targetVersion}-windows-x86_64"
			}

			fileOperations([
				fileDownloadOperation(
					password: '',
					proxyHost: '',
					proxyPort: '',
					targetFileName: ''+esBinaryFileName+'.zip',
					targetLocation: 'target',
					url: 'https://artifacts.elastic.co/downloads/elasticsearch/'+esBinaryFileName+'.zip',
					userName: '')
			])

			fileOperations([
				fileDownloadOperation(
					password: '',
					proxyHost: '',
					proxyPort: '',
					targetFileName: 'v'+targetVersion+'.zip',
					targetLocation: 'target',
					url: 'https://github.com/elastic/elasticsearch/archive/v'+targetVersion+'.zip',
					userName: '')
			])

			sh 'ls -l ${WORKSPACE}/target'

			withMaven(jdk: 'OpenJDK_11', maven: 'Maven_3.6.3', mavenSettingsConfig: custom_maven_settings, options: [artifactsPublisher(disabled: true)],  publisherStrategy: 'EXPLICIT') {
				sh 'chmod +x ${WORKSPACE}/build.sh'
				sh '${WORKSPACE}/build.sh "'+targetVersion+'" "'+remoteRepositoryURL+'" "'+remoteRepositoryID+'"'
			}

		}

	}

} catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
	currentBuild.result = "ABORTED"
	throw e
} catch (e) {
	currentBuild.result = "FAILURE"
	throw e
} finally {
	slack.notifyBuild(currentBuild.result)
	cleanWs()
}
