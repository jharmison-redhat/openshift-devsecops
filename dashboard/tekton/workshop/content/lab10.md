# Introduction

This lab will add the "Archive" stage to the pipeline

![Archive App Stage](images/openshift-pipeline-archive.png)

# Add Archive Stage

Archiving the built and tested application into a trusted repository is important to making sure we are building with trusted parts.  We assume this application is built properly and all the previous stages have passed.  With that confidence, our built and tested application should be immutable in a trusted repository.  The repository will version or audit any changes to the application, configuration, and dependencies.

We leveraged the maven nexus plugin for this deployment.  The mvn deploy step is the last step in the maven lifecycle.  The built application is archived into the nexus repository.  We can see it later once we run the pipeline.

The "-P nexus3" option activates the nexus3 profile defined in the configuration/cicd-settings-nexus3.xml

# Update pipeline

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: tasks-pipeline
spec:
  resources:
    - name: tasks-source-code
      type: git

  workspaces:
    - name: local-maven-repo

  tasks:
    - name: build-app
      # ... snipped for brevity ... 
    - name: test-app
      # ... snipped for brevity .. 
    - name: code-analysis
      # ... snipped for brevity
    - name: archive
      taskRef:
        kind: Task
        name: simple-maven
      params:
          - name: GOALS
            value: 
            - deploy
            - '-DskipTests=true'
            - '-Pnexus3' 
          - name: SETTINGS_PATH
            value: configuration/cicd-settings-nexus3.xml
          - name: POM_PATH
            value: pom.xml
      resources:
        inputs:
          - name: source
            resource: tasks-source-code
      workspaces:
        - name: maven-repo
          workspace: local-maven-repo
      runAfter:
          - test-app
          - code-analysis
```

One thing to call out here is that the `runAfter` attribute of the task allows us to wait for both of the tasks to complete (and be successful), before this task could run

# Test Your Pipeline

Either run the pipeline from the command line, or re-run the previous PipelineRun from the Console:
```bash
tkn pipeline start --resource tasks-source-code=tasks-source --workspace name=local-maven-repo,claimName=maven-repo-pvc tasks-pipeline --showlog
```

![Archive Pipeline Run Results](images/archive_pipeline_results.png)

Now we can view the contents of the Nexus repository. First, let's get the URL of the Nexus server:
```bash
oc get route -n devsecops nexus
NAME    HOST/PORT                                                                PATH   SERVICES   PORT   TERMINATION   WILDCARD
nexus   nexus-devsecops.apps.cluster-nisky-0450.nisky-0450.example.opentlc.com          nexus      8081                 None

```

With the Nexus route URL in hand, navigate to Nexus, click the Sign-In button in the upper-right corner, log in with your credentials (you will be asked tochange your password through the wizard - just keep the same credentials as before). Then, Navigate to Browse from the left-hand navigation menu, and click into the `maven-snapshots` repository. You will see the SNAPSHOT artifacts that have been created so far: 

![Nexus artifacts](images/nexus_artifacts_tasks.png)


# Conclusion

We have continued extending the pipeline using the `simple-maven` task, and we now have the artifact from the application build securely stored in the Nexus repository after it passes all the tests. This step in the pipeline also illustrates how to use more advanced flows where the flow of execution converges after executing more than one parallel task. 
