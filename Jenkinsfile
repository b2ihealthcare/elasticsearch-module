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

	node('build') {

		stage('Checkout repository') {
			checkout scm
		}

		stage('Build') {

			withMaven(jdk: 'OpenJDK_11', maven: 'Maven_3.6.3', mavenSettingsConfig: custom_maven_settings, options: [artifactsPublisher(disabled: true)],  publisherStrategy: 'EXPLICIT') {
				sh 'chmod +x build.sh'
				sh 'build.sh '+targetVersion+' '+remoteRepositoryURL+' '+remoteRepositoryID+''
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
}
