
# Introduction 

Before we dive into starting to build our pipeline, let's review some of the key concepts in Tekton

# Key Concepts


## Tasks and Steps, and Task Runs

So, here are the definitions:
* Step : Run commands in a container with volumes, env vars, etc
* Task : a list of steps that run sequentially in the same pod. 
* Task Run : an invocation of a task with inputs and outputs

A few things to highlight from the definitions above: 
* Steps are fairly low-level : they basically say "here, run this container, and then run this command in this container". 
* Steps in a task cannot take their own parameters beyond what's pre-defined in the Step specification. 
* The way you make the Task reusable is by taking in the values that the steps might need, and move them with parameters. In order to refer to the parameters in the body of the task (e.g. in steps) is by using the special `$(params.my-param-name)` syntax (if you wanted to use the `my-param-name`)
* Task runs are the runtime representation of a Task - where the task and the actual parameters with which the task was called with. The task runs provide the input to the tasks to execute with, e.g. parameters, resources, serivce accounts, workspaces
* Also note that because Steps in a Task execute in the same pod, they are able to share some local resources. 
  
Let's look at an example : 

```yaml
kind: Task
metadata:
name: maven
spec:
 params:
   - name: goal
     type: string
     default: package
 steps:
   - name: mvn
     image: maven:3.6.0-jdk-8-slim
     command: [ mvn ]
     args: [ $(params.goal) ]

```

There is quite a bit more to tasks, the gory details (such as resources, workspaces, etc) are available on the [Tekton Github](https://github.com/tektoncd/pipeline/blob/master/docs/tasks.md)

## Pipelines and Pipeline Runs

Let's start with some definitions: 
* Pipelines define the graph of task execution. They can also be parametrized with parameters, resources, and workspaces that need to be provided
* Pipeline Runs are again the construct that provides the actual values with which the pipelines are to be executed. The pipeline run executes the pipeline to completion, and creates TaskRuns that execute the tasks in the pipelines. Because different Tasks execute in different pods, they could run on different nodes, and if they need to share resources, they need to use a construct like a `workspace`

```yaml
apiVersion: tekton.dev/v1alpha1
kind: Pipeline
metadata:
  name: app-s2i-build
spec:
  resources:
    - name: app-git
      type: git
    - name: app-image
      type: image
  tasks:
    - name: build-app
      taskRef:
        kind: Task
        name: s2i-eap-7
      params:
        - name: TLSVERIFY
          value: 'false'
      resources:
        inputs:
          - name: source
            resource: app-git
        outputs:
          - name: image
            resource: app-image

```

The example pipeline above only has a single task. It defines the resources that it needs (a git repo and an image to output) and passes those values to the single task named `s2i-eap-7` that it executes with the parameters that it's given. 

## Pipeline Resources


The Tekton developers recognized that there are some some common elements of cloud native pipelines that are somewhat like parameters, but they are a bit more complex. Pipeline resources are inputs and outputs to tasks and pipelines. In Tasks and Pipelines they are defined by name and type. The example Pipeline above requires the following to be given to it: 
* An `app-git` pipeline resource, which is a Git repository. The same resource is then passed on to the `s2i-eap-7` task. 
* An `app-image` pipeline resource, which is an image reference. That image reference is passed to the `s2i-eap-7` task, and is the destination where the created image will be pushed. 

The most commonly used Pipeline Resources in Tekton are Git and Image resources, but there are others : e.g. Pull Requests, Cluster Resources, etc. The gory details are at [the Pipeline Resources Docs on GitHub](https://github.com/tektoncd/pipeline/blob/master/docs/resources.md)

Here's an example of a git Pipeline Resource:

```yaml
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: source
spec:
  params:
    - name: url
      value: >-
        https://gitea-server-devsecops.apps.cluster-nisky-73f7.nisky-73f7.example.opentlc.com/user3/openshift-tasks.git
    - name: revision
      value: dso4
  type: git

```

One final note about Pipeline Resource: you can reference the additional parameters of the Pipeline Resource in your Task or Pipeline definitions using the a similar variable substitution syntax, e.g. `$(resources.resource-name.resource-param)`. For example, if I'm using the `$(resources.source.path)` variable substitution in order to access the `path` value of the git resource named `source`

```yaml
apiVersion: tekton.dev/v1alpha1
kind: Task
metadata:
  name: maven-java8
spec:
  params:
    - default:
        - package
      description: maven goals to run
      name: GOALS
      type: array
    - default: configuration/cicd-settings-nexus3.xml
      description: location of the settings file
      name: settings-path
      type: string
  resources:
    inputs:
      - name: source
        type: git
  steps:
    - args:
        - $(params.GOALS)
        - '-s$(resources.source.path)/$(params.settings-path)'
      command:
        - /usr/bin/mvn
      image: 'gcr.io/cloud-builders/mvn:3.5.0-jdk-8'
      name: mvn-goals
      resources: {}
  workspaces:
    - name: maven-repo
```

## Workspaces

Workspaces provide for a mechanism for sharing data between tasks. Remember that each Task is started in a different pod, so if two tasks need to share some resources (e.g. some storage for the Maven process to download all dependencies that can be reused later on), a workspace comes in. 

Workspaces are similar to Pipeline Resources in that they are defined as "parameters" to Tasks and Pipelines, and need to be provided when a TaskRun or a PipelineRun is to be created 

## Others : Task Results, Triggers, Conditions

There is a lot more to learn in Tekton, but we will skip these for now. 

# Tools

As we saw so far, all parts of Tekton can be created and used through YAML. That is fantastic when we're looking to automate something, but it's a bit less than idea for day-to-day usage. 

For most of our work we will be using a combination of YAML and the OpenShift console, but all options are available

## OpenShift Console
The OpenShift Console provides some initial support for creating Pipelines directly in the OpenShift UI. 

![Web UI Console](images/console_pipeline_creation.png)

Similarly, if you try to start a Pipeline that requires some Pipeline Resources, the UI will prompt you to provide the necessary resources: 

![Pipeline Run Resources](images/pipelinerun_resources_ui.png)


While the majority of Tekton components are still defined in YAML, this area is quickly improving. 

*One Caveat* : in OpenShift 4.4, the UI does not yet provide a way to pass in a Workspace to a pipeline that is defined with one. For that reason, if you are working with a pipeline that needs a Workspace, at least the initial Pipeline Run needs to be created in YAML, and then follow-up Pipeline Runs can just be kicked off using the "Rerun" option on Pipeline Runs. 

## Command line tools

Finally, any self-respecting project these days has to have a set of command line tools for simplifying the interactions. In this case, the tool is called `tkn` and is available to download from the "Command Line Tools" sub-menu of the Help/Question Mark menu in the upper right corner of the OpenShift Console. 

![Command line tools popup](images/cmd_line_tools_help.png)

![Tkn Download](images/cmd_line_tools_download.png)

Here's an example of showing the available pipelines in the user1-cicd project

```shell
$ tkn pipeline ls -n user1-cicd
NAME                           AGE           LAST RUN                              STARTED       DURATION    STATUS
app-s2i-build                  8 hours ago   app-s2i-build-fnu9n4                  3 hours ago   1 minute    Succeeded
build-test-deploy-app-to-dev   8 hours ago   build-test-deploy-app-to-dev-9bdjue   3 hours ago   3 minutes   Succeeded
deploy-app-to-stage            8 hours ago   ---                                   ---           ---         ---

```

Similarly, kicking off a pipeline offers prompts for providing the required Pipeline Resources:

```bash
$ tkn pipeline start app-s2i-build -n user1-cicd
? Choose the git resource to use for app-git:  [Use arrows to move, type to filter]
> source (https://gitea-server-devsecops.apps.cluster-nisky-73f7.nisky-73f7.example.opentlc.com/user1/openshift-tasks.git#dso4)
? Choose the image resource to use for app-image:  [Use arrows to move, type to filter]
  image (quay.apps.cluster-nisky-73f7.nisky-73f7.example.opentlc.com/user1/openshift-tasks)
> internal-reg-image (image-registry.openshift-image-registry.svc.cluster.local:5000/user1-cicd/openshift-tasks:latest)
  create new "image" resource
Pipelinerun started: app-s2i-build-run-f2j6t
```
