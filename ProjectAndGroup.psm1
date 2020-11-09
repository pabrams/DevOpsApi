#
# FileName : ProjectAndGroup.psm1
# Data     : 02/09/2018
# Purpose  : this module will create a project and groups for a project
#           This script is for demonstration only not to be used as production code
#
# last update 8/1/2019

function CreateVSTSProject () {
    Param(
        [Parameter(Mandatory = $true)]
        $userParams
    )
      
    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail

    # get process id & variables needed
    $processId = GetVSTSProcesses -userParams $userParams -authorization $authorization
    $name = $userParams.ProjectName
    $description = $userParams.description 

    # json body to create project
    $v1 = @{
        name = $name
        description = $description
        capabilities = @{ versioncontrol = @{ sourceControlType = "Git" } 
            processTemplate = @{ templateTypeId = $processId} 
        }
    }
    $valJson = ConvertTo-Json -InputObject $v1
   
    try {
        # check if project already exists
        $projectUri = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/defaultcollection/_apis/projects?api-version=2.0-preview"
        $currProjects = Invoke-RestMethod -Uri $projectUri -Method Get -ContentType "application/json" -Headers $authorization 

        $fnd = $currProjects.value | Where-Object {$_.name -eq $name}
        IF (![string]::IsNullOrEmpty($fnd)) {
            Write-Host "Project found"
            Return $fnd.name
        } 
        
        # project does not exist, create new one
        $projectUri = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/defaultcollection/_apis/projects?api-version=2.0-preview"
        $return = Invoke-RestMethod -Uri $projectUri -Method Post -ContentType "application/json" -Headers $authorization -Body $valJson
        return $return
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-Host "Project Exists Error : " + $ErrorMessage + " iTEM : " + $FailedItem
    }
}

Function AddProjectTeams() {
    Param(
        [Parameter(Mandatory = $true)]
        $userParams
    )
            
    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail
    
    # add / update groups in project
    foreach ( $item in $userParams.Teams) {
        $tmData = @{ name = $item.name
            description = $item.description
        }

        $tmJson = ConvertTo-Json -InputObject $tmData
        $projectUri = "https://" + $userParams.VSTSMasterAcct + ".VisualStudio.com/DefaultCollection/_apis/projects/" + $userParams.ProjectName + "/teams?api-version=2.2"

        # Add team
        try {
            Invoke-RestMethod -Uri $projectUri -Method Post -ContentType "application/json" -Headers $authorization -Body $tmJson            
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
        }
    }  

}

##############################
#
# doc : https://www.visualstudio.com/en-us/docs/integrate/api/graph/groups#create-a-group-at-the-account-level
##############################
function AddVSTSGroupAndUsers() {
    Param(
        [Parameter(Mandatory = $true)]
        $userParams 
    )

    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail

   try {

        # first loop thru the teams and add the users to the teams
        foreach ( $item in $userParams.Teams) {
         
            # find the group if it exists
            $fnd = Get-GroupInfo -userParams $userParams -groupname $item.name 
        
            IF (![string]::IsNullOrEmpty($fnd)) {

                Write-Host "Team :" + $fnd.displayName + " Found, Descriptor : " + $fnd.descriptor

                foreach ( $usr in $item.users){

                    # add user to group
                    $userData = @{principalName = $usr}
                    $json = ConvertTo-Json -InputObject $userData

                    $adduserUri = "https://" + $userParams.VSTSMasterAcct + ".vssps.visualstudio.com/_apis/graph/users?groupDescriptors=" + $fnd.descriptor + "&api-version=4.0-preview"
                    $grp =  Invoke-RestMethod -Uri $adduserUri -Method Post -Headers $authorization -ContentType "application/json" -Body $json
                }
            } 
        }

        # now loop thru the VSTS groups and add users and groups as needed
        foreach ($item in $userParams.VSTSGroups)
        {
            # create group header
            $tmData = @{ displayName = $item.name
                description = $item.description
            }
            $tmJson = ConvertTo-Json -InputObject $tmData

            # add / group 
            $projectUri = "https://" + $userParams.VSTSMasterAcct + ".vssps.visualstudio.com/_apis/graph/groups?api-version=4.0-preview"
            $fnd = Invoke-RestMethod -Uri $projectUri -Method Post -Headers $authorization  -ContentType "application/json" -Body $tmJson       
    
            IF (![string]::IsNullOrEmpty($fnd)) {

                Write-Host "Team :" + $fnd.displayName + " Found, Descriptor : " + $fnd.descriptor

                foreach ( $usr in $item.users){

                    # add user to group
                    $userData = @{principalName = $usr}
                    $json = ConvertTo-Json -InputObject $userData

                    $adduserUri = "https://" + $userParams.VSTSMasterAcct + ".vssps.visualstudio.com/_apis/graph/users?groupDescriptors=" + $fnd.descriptor + "&api-version=4.0-preview"
                    $grp =  Invoke-RestMethod -Uri $adduserUri -Method Post -Headers $authorization -ContentType "application/json" -Body $json
                }
            } 
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
    }

}

function Get-ApprovalsByEnvironment()
{
    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        [Parameter(Mandatory = $true)]
        $outFile,
        [Parameter(Mandatory = $false)]
        $EnvToReport
    )

    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail

    # get list of environments
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/environments/list?view=azure-devops-rest-6.1
    # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/environments?api-version=6.1-preview.1
    $envUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/distributedtask/environments?api-version=6.1-preview.1"
    $allEnvs = Invoke-RestMethod -Uri $envUri -Method Get -Headers $authorization -Verbose
    Write-Host $allEnvs.count
    Write-Output "" | Out-File $outFile 

    # environments to report on null = all
    IF (![string]::IsNullOrEmpty($EnvToReport)) 
    {
        $envMain = $allEnvs.value | Where-Object {$_.name -eq $EnvToReport }
    }
    else
    {
        $envMain = $allEnvs.value 
    }

    foreach ($Env in $envMain)
    {
        Write-Output "" | Out-File $outFile -Append
        Write-Output "Environment : " $Env.name | Out-File $outFile -Append -NoNewline
        Write-Output "" | Out-File $outFile -Append

        # get individual environment with resources if available
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/environments/get?view=azure-devops-rest-6.1
        # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/environments/{environmentId}?expands={expands}&api-version=6.1-preview.1
        $envUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/distributedtask/environments/" + $Env.id + "?expands=resourceReferences&api-version=6.1-preview.1"
        $EnvwResources = Invoke-RestMethod -Uri $envUri -Method Get -Headers $authorization -Verbose
        for ($r = 0; $r -lt $EnvwResources.resources.length; $r++) 
        {
            # get the resources for this environment
            switch ($EnvwResources.resources[$r].type )
            {
                "kubernetes" { 
                    # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/kubernetes/get?view=azure-devops-rest-6.1
                    # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/environments/{environmentId}/providers/kubernetes/{resourceId}?api-version=6.1-preview.1
                    $kubUrl = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/distributedtask/environments/" + $Env.id + "/providers/kubernetes/" + $EnvwResources.resources[$r].id + "?api-version=6.1-preview.1"
                    $KubResource = Invoke-RestMethod -Uri $kubUrl -Method Get -Headers $authorization -Verbose

                 }

                 "virtualMachine" {

                 }

                 "virtualMachine"{

                 }

                 "generic"{

                 }

                 "undefined"{

                 }

                Default {}
            }
        }      

        # get environment deployment record - this is a list of deployments
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/environmentdeployment%20records/list?view=azure-devops-rest-6.1
        # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/environments/{environmentId}/environmentdeploymentrecords?api-version=6.1-preview.1
        $envDepUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/distributedtask/environments/" + $Env.id + "/environmentdeploymentrecords?api-version=6.1-preview.1"
        $EnvDeps = Invoke-RestMethod -Uri $envDepUri -Method Get -Headers $authorization -Verbose

        Write-Output " Number of Deployments  :" $EnvDeps.count | Out-File $outFile -Append -NoNewline
        Write-Output "" | Out-File $outFile -Append

        foreach ($Deploy in $EnvDeps.value) 
        {
            # get build in the deployments
            # GET https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}?api-version=6.1-preview.6
            $DepBuildUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/builds/" + $deploy.owner.id + "?api-version=6.1-preview.6"
            $DepBuild = Invoke-RestMethod -Uri $DepBuildUri -Method Get -Headers $authorization -Verbose
    
            # get build timeline 
            # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/timeline/get?view=azure-devops-rest-6.1
            # GET https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}/timeline/{timelineId}?api-version=6.1-preview.2
            $BuildTimelineUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/builds/" + $deploy.owner.id + "/timeline?api-version=6.1-preview.2"
            $BuildTimeLine = Invoke-RestMethod -Uri $BuildTimelineUri -Method Get -Headers $authorization -Verbose
        
            # filter timeline by stages,job,tasks, etc
            $tmStages = $BuildTimeLine.records | Where-Object { $_.type -eq "Stage" } | Sort-Object -Property order
            $tmJobs = $BuildTimeLine.records | Where-Object { $_.type -eq "Job" } | Sort-Object -Property order
            $tmTasks = $BuildTimeLine.records | Where-Object { $_.type -eq "Task" } | Sort-Object -Property order
            $tmPhase = $BuildTimeLine.records | Where-Object { $_.type -eq "Phase" } | Sort-Object -Property order

            $tmCheckPoint = $BuildTimeLine.records | Where-Object { $_.type -eq "CheckPoint" } | Sort-Object -Property order        
            $tmCpApproval = $BuildTimeLine.records | Where-Object { $_.type -eq "Checkpoint.Approval" } | Sort-Object -Property order
            $tmCpTaskChk = $BuildTimeLine.records | Where-Object { $_.type -match "Checkpoint.TaskCheck" } | Sort-Object -Property order

            # get stages
            # https://dev.azure.com/<ORG_NAME>/<PROJECT_NAME>/_build/results?buildId=1915&__rt=fps&__ver=2 
            #$stagesUrl = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_build/results?buildId=" + $deploy.owner.id + "&__rt=fps&__ver=2"
            #$stageResults = Invoke-RestMethod -Uri $stagesUrl -Method Get -Headers $authorization 
            #$stageList = $stageResults.fps.dataProviders.data.'ms.vss-build-web.run-details-data-provider'.stages
            
            Write-Host "   Deployment :" $Deploy.owner.name " on " $Deploy.definition.name " Status :" $DepBuild.status " Results : " $DepBuild.result
            Write-Host "        Stage : " $stg.name " Assigned approvers : " $appData.approvals.steps.length

            Write-Output "" | Out-File $outFile -Append            
            Write-Output "   Deployment :" $Deploy.owner.name " on " $Deploy.definition.name " Status :" $DepBuild.status " Results : " $DepBuild.result | Out-File $outFile -Append -NoNewline
            Write-Output "" | Out-File $outFile -Append

            # for each stage find the list of approvers and actual approvers using undocumented API found in f12 of portal
            foreach ($stg in $tmStages) 
            {
                $tmData =  @{
                    contributionIds =  @("ms.vss-build-web.checks-panel-data-provider");
                    dataProviderContext = @{
                        properties = @{
                            buildId =  $deploy.owner.id.ToString();
                            stageIds = $stg.id ;  
                            checkListItemType = 1;   
                            sourcePage = @{
                                url = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_build/results?buildId=" + $deploy.owner.id + "&view=results";
                                routeId = "ms.vss-build-web.ci-results-hub-route";
                                routeValues = @{
                                    project =  $userParams.ProjectName;
                                    viewname = "build-results";
                                    controller = "ContributedPage";
                                    
                                }
                            }                     
                        }
                    }
                }
                $acl = ConvertTo-Json -InputObject $tmData -depth 32
            
                # undocumented api call to get list of approvers for a given stage
                # https://dev.azure.com/fdx-strat-pgm/_apis/Contribution/HierarchyQuery/project/633b0ef1-c219-4017-beb0-8eb49ff55c35?api-version=5.0-preview.1
                $approvalURL = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/_apis/Contribution/HierarchyQuery/project/" + $Env.project.id + "?api-version=5.0-preview.1"
                $ApprlResults = Invoke-RestMethod -Uri $approvalURL -Method Post -Headers $authorization  -ContentType "application/json" -Body $acl

                # get the approval data
                $appData = $ApprlResults.dataproviders.'ms.vss-build-web.checks-panel-data-provider'
               
                Write-Output "        Stage : " $stg.name " Assigned approvers : " $appData.approvals.steps.length | Out-File $outFile -Append -NoNewline
                Write-Output "" | Out-File $outFile -Append

                # if approvals exist for this stage get them               
                foreach ($item in $appData.approvals.steps) {
                    Write-Host "    Assigned approver : "  $item.assignedApprover.displayName                  

                    IF (![string]::IsNullOrEmpty($item.actualApprover)) 
                    {
                        # if actual approver is not same as assigned approver 
                        if($item.actualApprover.displayName -ne $item.assignedApprover.displayName )
                        {
                            Write-Output "          Actual approver  : " $item.actualApprover.displayName " : on behalf of :" $item.assignedApprover.displayName " Date : " $item.lastModifiedOn  " Comment : " $item.comment | Out-File $outFile -Append -NoNewline
                            Write-Output "" | Out-File $outFile -Append    
                        }else
                        {
                            Write-Output "          Actual approver  : " $item.actualApprover.displayName " Date : " $item.lastModifiedOn  " Comment : " $item.comment | Out-File $outFile -Append -NoNewline
                            Write-Output "" | Out-File $outFile -Append                                
                        }

                    }
                    else
                    {
                        #Write-Output "         Assigned approver : "  $item.assignedApprover.displayName| Out-File $outFile -Append -NoNewline
                       # Write-Output "" | Out-File $outFile -Append
                    }
                }
            }

            # loop thru each approval in the pipeline and get the approval record
            #foreach ($chApp in $tmCpApproval) 
            #{
            #    #Approval – Get: Get https://dev.azure.com/{organization}/{project}/_apis/pipelines/approvals/{approvalId}
            #    $approvalURL = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/pipelines/approvals/" + $chApp.Id
            #    $Approval = Invoke-RestMethod -Uri $approvalURL -Method Get -Headers $authorization -Verbose
            #    Write-Host $Approval
            #}

        }

    }

    # get list of pipelines
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/pipelines/pipelines/list?view=azure-devops-rest-6.1
    # GET https://dev.azure.com/{organization}/{project}/_apis/pipelines?api-version=6.1-preview.1
   # $pipelineUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/pipelines?api-version=6.1-preview.1"
   # $allPipelines = Invoke-RestMethod -Uri $pipelineUri -Method Get -Headers $authorization -Verbose
   # Write-Host $allPipelines.count

    # get all runs for a pipeline
    #foreach ($pipeline in $allPipelines.value)
    #{
        # get runs for a pipeline
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/pipelines/runs/list?view=azure-devops-rest-6.1
        # GET https://dev.azure.com/{organization}/{project}/_apis/pipelines/{pipelineId}/runs?api-version=6.1-preview.1
    #    $runUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/pipelines/" + $pipeline.id + "/runs?api-version=6.1-preview.1"
    #    $allruns = Invoke-RestMethod -Uri $runUri -Method Get -Headers $authorization -Verbose
    #    Write-Host $allruns.count

    #    foreach ($run in $allruns.value) 
    #    {
    #        # get detail of a run 
    #        # https://docs.microsoft.com/en-us/rest/api/azure/devops/pipelines/runs/get?view=azure-devops-rest-6.1
    #        # GET https://dev.azure.com/{organization}/{project}/_apis/pipelines/{pipelineId}/runs/{runId}?api-version=6.1-preview.1
    #        $runDetailUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/pipelines/" + $pipeline.id + "/runs/" + $run.id + "?api-version=6.1-preview.1"
    #        $runDetail = Invoke-RestMethod -Uri $runDetailUri -Method Get -Headers $authorization -Verbose
    #        Write-Host $runDetail.count
    #
    #    }
    #
    #           
    #}


}

function Get-BuildDetailsByProject(){
    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        [Parameter(Mandatory = $true)]
        $outFile,
        [Parameter(Mandatory = $false)]
        $FolderName
    )
    #
    # this function will list all builds in a given project
    #

    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail
    
    # get list of folders
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/folders/list?view=azure-devops-rest-6.0
    # GET https://dev.azure.com/{organization}/{project}/_apis/build/folders/{path}?api-version=6.0-preview.2
    $folderUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/folders?api-version=6.0-preview.2"
    $allFlders = Invoke-RestMethod -Uri $folderUri -Method Get -Headers $authorization -Verbose

    # filter by folder if needed
    if (![string]::IsNullOrEmpty($FolderName))
    {
        $allFolders = $allFlders.value | Where-Object { $_.path -match $FolderName}
    }
    else 
    {
        $allFolders = $allFldrs.value
    }

    Write-Output "" $Folder.path  | Out-File $outFile 
    Write-Output "Orginization / Project:" $userParams.VSTSMasterAcct " / " $userParams.ProjectName | Out-File $outFile -Append -NoNewline

    # loop thru each folder and get build definitions
    foreach ($Folder in $allFolders) 
    {
        Write-Host "Folder : " $Folder.path 

        Write-Output ""  | Out-File $outFile -Append
        Write-Output "     Folder : " $Folder.path  | Out-File $outFile -Append -NoNewline
        Write-Output ""  | Out-File $outFile -Append

        # get list build definitions by folder
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/definitions/list?view=azure-devops-rest-6.1
        # GET https://dev.azure.com/{organization}/{project}/_apis/build/definitions?name={name}&repositoryId={repositoryId}&repositoryType={repositoryType}&queryOrder={queryOrder}&$top={$top}&continuationToken={continuationToken}&minMetricsTime={minMetricsTime}&definitionIds={definitionIds}&path={path}&builtAfter={builtAfter}&notBuiltAfter={notBuiltAfter}&includeAllProperties={includeAllProperties}&includeLatestBuilds={includeLatestBuilds}&taskIdFilter={taskIdFilter}&processType={processType}&yamlFilename={yamlFilename}&api-version=6.1-preview.7
        $folderUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/definitions?path=" +$Folder.path + "&includeAllProperties=true&includeLatestBuilds=true&api-version=6.1-preview.7"
        $AllDefinitions = Invoke-RestMethod -Uri $folderUri -Method Get -Headers $authorization 
              
        # get builds for each definition
        Write-Host "       Build Definitions found: " $AllDefinitions.count
        Write-Output "     Build Definitions Found : " $AllDefinitions.count  | Out-File $outFile -Append -NoNewline
        Write-Output "" | Out-File $outFile -Append        

        foreach ($BuildDef in $AllDefinitions.value) 
        {
            # get builds for each definition
            # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds/list?view=azure-devops-rest-6.1
            # GET https://dev.azure.com/{organization}/{project}/_apis/build/builds?definitions={definitions}&queues={queues}&buildNumber={buildNumber}&minTime={minTime}&maxTime={maxTime}&requestedFor={requestedFor}&reasonFilter={reasonFilter}&statusFilter={statusFilter}&resultFilter={resultFilter}&tagFilters={tagFilters}&properties={properties}&$top={$top}&continuationToken={continuationToken}&maxBuildsPerDefinition={maxBuildsPerDefinition}&deletedFilter={deletedFilter}&queryOrder={queryOrder}&branchName={branchName}&buildIds={buildIds}&repositoryId={repositoryId}&repositoryType={repositoryType}&api-version=6.1-preview.6
            $BuildUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/builds?definitions=" + $BuildDef.id + "&queryOrder=startTimeDescending&api-version=6.1-preview.6"
            $allBuilds = Invoke-RestMethod -Uri $BuildUri -Method Get -Headers $authorization 

            Write-Output "" | Out-File $outFile -Append        
            Write-Host $BuildDef.name 
            Write-Output "" | Out-File $outFile -Append
            Write-Output "         Build Definition : "  $BuildDef.name  "   Builds in definition : " $allBuilds.count | Out-File $outFile   -Append -NoNewline
            Write-Output ""  | Out-File $outFile -Append

            Write-Host "        Builds found by definition: " $allBuilds.count
            $latestCompleteBuildInfo = $BuildDef.latestCompletedBuild
            $latest = ""

            # get all work items associated to the build
            for ($b = 0; $b -lt $allBuilds.Count; $b++) {
                
                $build = $allBuilds.value[$b]
                
                # if latest build and we have already displayed the latest build skip
                if( $latestCompleteBuildInfo.id -eq $build.id -and $latest -ne "")
                {
                    continue
                }

                # find latest build and print it first
                if($latest -eq "" )
                {
                    $build = $allBuilds.value | Where-Object { $_.id -match $latestCompleteBuildInfo.id }
                    # if not found ie no latest build use next build in list
                    IF ([string]::IsNullOrEmpty($build))
                    {
                        $build = $allBuilds.value[$b]
                    }else 
                    {
                        Write-Output ""  | Out-File $outFile -Append
                        Write-Output "        ======> Latest Build <======" | Out-File $outFile -Append -NoNewline
                        $latest = $build.id
                    }
                }

                Write-Host "Build ID: " $build.id " - Build Number : " $build.buildNumber    
                Write-Host "    Build Status: " $build.Status " - Result: " $build.result
                $def = $build.definition
                $repo = $build.repository
                $allTags = $build.tags
                $allPlans = $build.plans
    
                Write-Output ""  | Out-File $outFile -Append
                Write-Output "        --->Build ID: " $build.id " - Build Number : " $build.buildNumber | Out-File $outFile -Append -NoNewline
                Write-Output ""  | Out-File $outFile -Append
                Write-Output "            Build Status: " $build.Status " - Result: " $build.result  | Out-File $outFile   -Append -NoNewline
                Write-Output ""  | Out-File $outFile -Append
                Write-Output "            Requested by: " $def.name " - Start Time: " $build.startTime  "  Finish Time: " $build.finishTime | Out-File $outFile   -Append -NoNewline
                Write-Output ""  | Out-File $outFile -Append
                Write-Output "            Source Branch: " $build.sourceBranch " Repo : " $repo.name  | Out-File $outFile   -Append -NoNewline
                Write-Output ""  | Out-File $outFile -Append
               
                # get build changes
                # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds/get%20build%20changes?view=azure-devops-rest-6.1
                # GET https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}/changes?api-version=6.1-preview.2
                $bldChangegUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/builds/" + $Build.id + "/changes?api-version=6.1-preview.2"
                $bldChanges = Invoke-RestMethod -Uri $bldChangegUri -Method Get -Headers $authorization 

                Write-Output ""  | Out-File $outFile -Append
                Write-Output "            Builds changes found for this build: " $bldChanges.count  | Out-File $outFile -Append -NoNewline
                Write-Output ""  | Out-File $outFile -Append
                foreach ($bldChg in $bldChanges.value) 
                {
                    Write-Output "            Build Change: " $bldChg.message " Date Changed : " $bldChg.timestamp   "   Changed by: " $bldChg.'author'.DisplayName| Out-File $outFile   -Append -NoNewline
                    Write-Output ""  | Out-File $outFile -Append
                }
                Write-Output ""  | Out-File $outFile -Append

                # list all tags found
                for ($i = 0; $i -lt $allTags.length; $i++) {
                    Write-Output "                Tag : " $allTags[$i]  | Out-File $outFile   -Append -NoNewline
                    Write-Output ""  | Out-File $outFile -Append
                }
              
                # get code coverage for build
                # https://docs.microsoft.com/en-us/rest/api/azure/devops/test/code%20coverage/get%20build%20code%20coverage?view=azure-devops-rest-6.0
                # GET https://dev.azure.com/{organization}/{project}/_apis/test/codecoverage?buildId={buildId}&flags={flags}&api-version=6.0-preview.1
                $codeCvgUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/test/codecoverage?buildId=" + $Build.id + "&api-version=6.0-preview.1"
                $codeCvgForBuild = Invoke-RestMethod -Uri $codeCvgUri -Method Get -Headers $authorization 
                foreach ($codeCv in $codeCvgForBuild.value)
                {
                    Write-Host $codecv.length    
                }

                # get plan details
                #
              

                # get all artifacts for this build
                # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/artifacts/list?view=azure-devops-rest-6.0
                # GET https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}/artifacts?api-version=6.0
                $artifactUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/builds/" + $Build.id + "/artifacts?api-version=6.0"
                $allBuildartifacts = Invoke-RestMethod -Uri $artifactUri -Method Get -Headers $authorization 

                Write-Host "    Build Artifacts : " $allBuildartifacts.count
                Write-Output "            Artifacts Found: " $allBuildartifacts.count | Out-File $outFile   -Append -NoNewline
                Write-Output ""  | Out-File $outFile -Append
                foreach ($artifact in $allBuildartifacts.value) 
                {
                    $res = $artifact.resource
                    Write-Output "            Artifacts Name: " $artifact.name "   Artifacts Type: "  $res.type | Out-File $outFile   -Append -NoNewline
                    Write-Output ""  | Out-File $outFile -Append                    
                }

                try 
                {
                    #get build report
                    # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/report/get?view=azure-devops-rest-6.0
                    # GET https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}/report?api-version=6.0-preview.2
                    $buildReportUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/builds/" + $Build.id + "/report?api-version=6.0-preview.2"
                    $buildReport = Invoke-RestMethod -Uri $buildReportUri -Method Get -Headers $authorization     

                    $BuildRep = ConvertTo-Json -InputObject $buildReport -Depth 32
                    Write-Host $BuildRep
                }
                catch 
                {
                    $ErrorMessage = $_.Exception.Message
                    $FailedItem = $_.Exception.ItemName
                    # Write-Host "Security Error : " + $ErrorMessage + " iTEM : " + $FailedItem    
                }
                
                # get work all itemsfor this build
                # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds/get%20build%20work%20items%20refs?view=azure-devops-rest-6.1
                # GET https://dev.azure.com/{organization}/{project}/_apis/build/builds/{buildId}/workitems?api-version=6.1-preview.2
                $workItemUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/build/builds/" + $Build.id + "/workitems?api-version=6.1-preview.2"
                $allBuildWorkItems = Invoke-RestMethod -Uri $workItemUri -Method Get -Headers $authorization 
                
                Write-Host "            Work Items found in Build: " $allBuildWorkItems.count
                Write-Output "" | Out-File $outFile -Append
                Write-Output "             Work Items Found: " $allBuildWorkItems.count  | Out-File $outFile   -Append -NoNewline
                Write-Output "" | Out-File $outFile -Append

                # get individual work items assiciated to the build
                foreach ($workItems in $allBuildWorkItems.value) 
                {
                    # get individual work item
                    # https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/work%20items/get%20work%20item?view=azure-devops-rest-6.1
                    # GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems/{id}?api-version=6.1-preview.3
                    $BuildworkItemUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/wit/workitems/" + $workItems.id + "?api-version=6.1-preview.3" 
                    $WItems = Invoke-RestMethod -Uri $BuildworkItemUri -Method Get -Headers $authorization 
                    
                    $fld = $WItems.fields
                    $cls = $fld.'Microsoft.VSTS.Common.ClosedBy'
                    $ast = $fld.'System.AssignedTo'

                    Write-Host "        Work Item : " $fld.'System.Title'    $cls.displayName 
                    
                    Write-Output "" | Out-File $outFile -Append
                    Write-Output "               Work Item Id: " $WItems.id   "   Status : " $fld.'System.State'   "  Name : "  $fld.'System.Title' | Out-File $outFile   -Append -NoNewline
                    Write-Output "" | Out-File $outFile -Append
                    Write-Output "               Area Path : " $fld.'System.AreaPath' "  Iteration : " $fld.'System.IterationPath' | Out-File $outFile -Append -NoNewline
                    Write-Output "" | Out-File $outFile -Append
                    Write-Output "               Assigned To : " $ast.displayName  "  Type : " $fld.'System.WorkItemType' | Out-File $outFile -Append -NoNewline
                    Write-Output "" | Out-File $outFile -Append
                    Write-Output "               Closed by : " $cls.displayName   " Date Closed: " $fld.'Microsoft.VSTS.Common.ClosedDate' | Out-File $outFile -Append -NoNewline
                    Write-Output "" | Out-File $outFile -Append
                    Write-Output "               Origional Estimate : " $fld.'Microsoft.VSTS.Scheduling.OrigionalEstimate'   " Actual: " $fld.'Microsoft.VSTS.Scheduling.CompletedWork' | Out-File $outFile -Append -NoNewline
                    Write-Output "" | Out-File $outFile -Append
                }
                
            }


        }
           
        
    }
    
   

}

function Get-AllUSerMembership(){
    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        [Parameter(Mandatory = $true)]
        $outFile,
        [Parameter(Mandatory = $false)]
        $getAllProjects
    )

    #
    # this function will get a list of users from a given group using the identity api
    #

    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail

    # set output directory for data
    $outFile = $userParams.DataDirectory + $outFile

    # get all teams in org. need to see if group is a team or group
    # GET https://dev.azure.com/{organization}/_apis/teams?api-version=6.1-preview.3
    $teamUri = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/_apis/teams?api-version=6.1-preview.3"
    $allTeams = Invoke-RestMethod -Uri $teamUri -Method Get -Headers $authorization 

    # find groups in all ado projects
    $projectUri = "https://" + $userParams.VSTSMasterAcct + ".vssps.visualstudio.com/_apis/graph/groups?subjectTypes=vssgp&api-version=6.0-preview.1"
    $vssGroups = Invoke-RestMethod -Uri $projectUri -Method Get -Headers $authorization 

    $projectUri = "https://" + $userParams.VSTSMasterAcct + ".vssps.visualstudio.com/_apis/graph/groups?subjectTypes=aadgp&api-version=6.0-preview.1"
    $aadGroups = Invoke-RestMethod -Uri $projectUri -Method Get -Headers $authorization 
   
    $allGroups = @()
    $allGroups += $vssGroups.value
   
    # find groups for the current project
    if($getAllProjects -ne "True"){
        $fnd = $allGroups | Where-Object {$_.principalName -match  $userParams.ProjectName }
    }else {
        $fnd = $allGroups 
    }

    # add in the aad groups
    $fnd += $aadGroups.value

    Write-Output 'Project|Group Name|Type|Relationship|User Name|Email Address|Fedex ID' | Out-File -FilePath $outFile
    Write-Output " " | Out-File -FilePath $outFile -Append 

    foreach ($item in $fnd) {
        # find group memberships frm identity api
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/ims/identities/read%20identities?view=azure-devops-rest-6.1#examples
        
        # search by name and get direct membership: need to use direct here and in the following query to get all direct members and member of
        # to mimic whats in ADO
        # GET https://vssps.dev.azure.com/fabrikam/_apis/identities?searchFilter=General&filterValue=jtseng@vscsi.us&queryMembership=None&api-version=6.1-preview.1
        #
        $grpMemberUrl = "https://vssps.dev.azure.com/" + $userParams.VSTSMasterAcct + "/_apis/identities?searchFilter=General&filterValue="  + $item.principalName + "&queryMembership=direct&api-version=6.1-preview.1"
        $allGrpMembers = Invoke-RestMethod -Uri $grpMemberUrl -Method Get -Headers $authorization 

        Write-Host $item.principalName 

        # is this a team or group
        $prName = $item.principalName.Split('\')
        $projectName =  $prName[0].substring(1,$prname[0].length-2)
        $tm = $prName[1]

        $isTeam = $allTeams.value | Where-Object {($_.name -eq  $tm) -and ($_.projectName -eq $projectName)}
        $teamGroup = ""
        if ([string]::IsNullOrEmpty($isTeam)) 
        {
            $teamGroup = "G-Delivered"
        }else {
            $teamGroup = "T-Custom"
        }

        if($allGrpMembers.value[0].members -ne 0)
        {        
            # get members this user is a member of
            foreach ($member in $allGrpMembers.value[0].memberOf ) {

                # now search by descriptor. sisnce we have all the direct members of the group  value[0].members
                $memberUrl = "https://vssps.dev.azure.com/" + $userParams.VSTSMasterAcct + "/_apis/identities?descriptors="  + $member + "&queryMembership=direct&api-version=6.1-preview.1"            
                $curUser = Invoke-RestMethod -Uri $memberUrl -Method Get -Headers $authorization 
                                                    
                Write-Host $item.principalName 
                
                # get project name
                $prj1 = $item.principalName.SPlit('\')
                $prjName = $prj1[0].substring(1,$prj1[0].length-2)

                Write-Output $prjName"|" | Out-File -FilePath $outFile -Append -NoNewline                      
                Write-Output $item.displayName "|" | Out-File -FilePath $outFile -Append -NoNewline  
                Write-Output $teamGroup "|" | Out-File -FilePath $outFile -Append -NoNewline  
                Write-Output  "Member-Of|" | Out-File -FilePath $outFile -Append -NoNewline
                Write-Output $curUser.value[0].providerDisplayName "|" | Out-File -FilePath $outFile -Append -NoNewline
                
                $email = $curUser.value[0].properties.Account.'$value'
                $fnd = $email | Select-String -Pattern '.com' -SimpleMatch
                IF ([string]::IsNullOrEmpty($fnd)) {
                    $email = " Group - No Email listed"
                }

                Write-Output $email "|" | Out-File -FilePath $outFile -Append -NoNewline 
                Write-Output $curUser.value[0].properties.DirectoryAlias.'$value' | Out-File -FilePath $outFile -Append -NoNewline 
                Write-Output " " | Out-File -FilePath $outFile -Append                   
            }   
            
            # get members this user is a direct member
            foreach ($member in $allGrpMembers.value[0].members ) {
                # now search by descriptor. sisnce we have all the direct members of the group  value[0].members
                $memberUrl = "https://vssps.dev.azure.com/" + $userParams.VSTSMasterAcct + "/_apis/identities?descriptors="  + $member + "&queryMembership=direct&api-version=6.1-preview.1"            
                $curUser = Invoke-RestMethod -Uri $memberUrl -Method Get -Headers $authorization 
                
                # get list to additional memberships
                Write-Host $curUser.value[0].providerDisplayName
                Write-Host $item.principalName 

                # get project name
                $prj1 = $item.principalName.SPlit('\')
                $prjName = $prj1[0].substring(1,$prj1[0].length-2)
 
                Write-Output $prjName"|" | Out-File -FilePath $outFile -Append -NoNewline                      
                Write-Output $item.displayName "|" | Out-File -FilePath $outFile -Append -NoNewline  
                Write-Output $teamGroup "|" | Out-File -FilePath $outFile -Append -NoNewline  
                Write-Output  "Member|" | Out-File -FilePath $outFile -Append -NoNewline
                Write-Output $curUser.value[0].providerDisplayName  "|" | Out-File -FilePath $outFile -Append -NoNewline
                
                $email = ""
                $email = $curUser.value[0].properties.Account.'$value'
                $fnd = $email | Select-String -Pattern '.com' -SimpleMatch
                IF ([string]::IsNullOrEmpty($fnd)) {
                    $email = " Group - No Email listed"
                }else 
                {
                    #GET https://vsaex.dev.azure.com/{organization}/_apis/userentitlements/{userId}?api-version=5.1-preview.2
                    ## get user info . need last access date, create date and license type
                    #$userUrl = "https://vsaex.dev.azure.com/" + $userParams.VSTSMasterAcct + "/_apis/userentitlements/"  + $curUser.value[0].id + "?api-version=6.0-preview.3"            
                    #$UserDetails = Invoke-RestMethod -Uri $userUrl -Method Get -Headers $authorization 
                }
                
                Write-Output $email "|" | Out-File -FilePath $outFile -Append -NoNewline 
                Write-Output $curUser.value[0].properties.DirectoryAlias.'$value' | Out-File -FilePath $outFile -Append -NoNewline 
                Write-Output " " | Out-File -FilePath $outFile -Append                     
            
            }   
        }
        else {
            
            # get project name
            $prj1 = $item.principalName.SPlit('\')
            $prjName = $prj1[0].substring(1,$prj1[0].length-2)

            Write-Output $prjName"|" | Out-File -FilePath $outFile -Append -NoNewline                      
            Write-Output $item.displayName "|" | Out-File -FilePath $outFile -Append -NoNewline  
            Write-Output $teamGroup "|" | Out-File -FilePath $outFile -Append -NoNewline  
            Write-Output  "Member|" | Out-File -FilePath $outFile -Append -NoNewline
            Write-Output   "No Members Found|" | Out-File -FilePath $outFile -Append -NoNewline            
            Write-Output  "|" | Out-File -FilePath $outFile -Append -NoNewline 
            Write-Output " " | Out-File -FilePath $outFile -Append                     
        
        }
    }


}


function Get-GroupInfo() {
    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        [Parameter(Mandatory = $true)]
        $groupname
    )
    
    try {
        
        # Base64-encodes the Personal Access Token (PAT) appropriately
        $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail

        # find groups
        $projectUri = "https://" + $userParams.VSTSMasterAcct + ".vssps.visualstudio.com/_apis/graph/groups?api-version=4.0-preview"
        $allGroups = Invoke-RestMethod -Uri $projectUri -Method Get -Headers $authorization 
    
        $fnd = $allGroups.value | Where-Object {$_.displayName -eq $groupname }
        IF (![string]::IsNullOrEmpty($fnd)) {
           if($fnd.LongLength -ne 1)
           {
               foreach($item in $fnd)
               {
                   if($item.principalName -eq "[" + $userParams.ProjectName + "]\" + $groupname)
                   {
                       return $item;
                   }
               }
           }
            return $fnd;
        }

    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
    }
}

function ListGitBranches(){

    # this function will list the GIT repos
    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        $outFile
    )

    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail


     try {
             
        # find git repo
        $listProviderURL = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/git/repositories?api-version=5.0"
        $repo = Invoke-RestMethod -Uri $listProviderURL -Method Get -ContentType "application/json" -Headers $authorization 
    
       
        try {
            Write-Output "  " | Out-File -FilePath $outFile -Append
            Write-Output " Repositories  " | Out-File -FilePath $outFile -Append
            
            # find branches for given repo
            $listProviderURL = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/git/repositories/" + $repo.value[0].Id + "/refs?api-version=5.0"
            $branchlist = Invoke-RestMethod -Uri $listProviderURL -Method Get -ContentType "application/json" -Headers $authorization 

            foreach ($item in $branchlist.value) {
                Write-Host "Repositories : " $item.name 
                Write-Output "  " | Out-File -FilePath $outFile -Append
                Write-Output '   Repositories : '$item.name | Out-File -FilePath $outFile -Append -NoNewline
            }    
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
        }          
    
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
    }
       
}

function AddGitBranchFromMaster(){

    # https://github.com/microsoft/azure-devops-dotnet-samples/tree/master/ClientLibrary/Samples/Git
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/git/refs/update%20refs?view=azure-devops-rest-5.0
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/git/refs/update%20refs?view=azure-devops-rest-5.0#create/update/delete_a_ref_by_repositoryid
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/source%20providers/list%20branches?view=azure-devops-rest-5.0
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/source%20providers/list%20repositories?view=azure-devops-rest-5.0

    # this function add a branch from the master branch
    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        [Parameter(Mandatory = $true)]
        $branchToCreate
    )

    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail

     try {
             
        # find git repo
        $listProviderURL = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/git/repositories?api-version=5.0"
        $repo = Invoke-RestMethod -Uri $listProviderURL -Method Get -ContentType "application/json" -Headers $authorization 
       
        try {
            
            # find branches for given repo
            $URL = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/git/repositories/" + $repo.value[0].Id + "/refs?api-version=5.0"
            $branchlist = Invoke-RestMethod -Uri $URL -Method Get -ContentType "application/json" -Headers $authorization 

            # need the repo id of master to create or delete branches
            $Masterid  = ($branchlist.value | Where-Object {$_.name -eq "refs/heads/master"}).objectId
            Write-Host "Master repo " $Masterid

            # create new branch payload newObjectId is the Object id of the master branch
            # to add new branch, oldObjectid = 40 0's
            $payload = @( @{
                        name = $branchToCreate 
                        oldObjectId = "0000000000000000000000000000000000000000"
                        newObjectId = $Masterid                        
                     })    
            $tmJson = ConvertTo-Json -InputObject $payload                        
            $newBranch = Invoke-RestMethod -Uri $URL -Method Post -ContentType "application/json" -Headers $authorization -Body $tmJson  
            
            $outData = ConvertTo-Json -InputObject $newBranch    
            Write-Host  $outData

        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
        }          
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
    }
       
}

function DeleteGitBranchByPath(){

    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        [Parameter(Mandatory = $true)]
        $branchPath
    )

    try {
        
            # Base64-encodes the Personal Access Token (PAT) appropriately
            $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail

            # find git repo
            $listProviderURL = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/git/repositories?api-version=5.0"
            $repo = Invoke-RestMethod -Uri $listProviderURL -Method Get -ContentType "application/json" -Headers $authorization 
       
            # get master branch id
            $URL = "https://dev.azure.com/" + $userParams.VSTSMasterAcct + "/" + $userParams.ProjectName + "/_apis/git/repositories/" + $repo.value[0].Id + "/refs?api-version=5.0"
            $branchlist = Invoke-RestMethod -Uri $URL -Method Get -ContentType "application/json" -Headers $authorization 

            # need the repo id of master to create or delete branches
            $Masterid  = ($branchlist.value | Where-Object {$_.name -eq "refs/heads/master"}).objectId
            Write-Host "Master repo " $Masterid

            # delete branch  
            # newObjectid is 40 o's old Objectid is object id master branch
            $payload = @( @{
                name = $branchPath
                newObjectId = "0000000000000000000000000000000000000000"
                oldObjectId = $Masterid                     
            })    
            
            $tmJson = ConvertTo-Json -InputObject $payload
            $delBranch = Invoke-RestMethod -Uri $URL -Method Post -ContentType "application/json" -Headers $authorization -Body $tmJson  
          
            $outData = ConvertTo-Json -InputObject $delBranch    
            Write-Host  $outData

    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
    }
}

function CreateVSTSGitRepo() {
    Param(
        [Parameter(Mandatory = $true)]
        $userParams
    )
   
	# Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail

    # get project id
    $projectUri = "https://" + $userParams.VSTSMasterAcct + ".VisualStudio.com/DefaultCollection/_apis/projects/" + $userParams.ProjectName +"?api-version=1.0"
    $return = Invoke-RestMethod -Uri $projectUri -Method Get -ContentType "application/json" -Headers $authorization 

    IF ([string]::IsNullOrEmpty($return)) {
        $projId = $return.id

        # create json body for request
        $repo = @{name = $userParams.RepositoryName
            project = @{id = $projId}
        }
        $tmJson = ConvertTo-Json -InputObject $repo

        # REST call to create Git Repo
        $projectUri = "https://" + $userParams.VSTSMasterAcct + ".VisualStudio.com/DefaultCollection/_apis/git/repositories?api-version=1.0"

        try {

            $return = Invoke-RestMethod -Uri $projectUri -Method Post -ContentType "application/json" -Headers $authorization -Body $tmJson
            return $return
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
        }
    }
    else {
        return $return
    }
}

function AddUsersToGroup() {
    Param(
        [Parameter(Mandatory = $true)]
        $vstsAccount,
        [Parameter(Mandatory = $true)]
        $userEmail,
        [Parameter(Mandatory = $true)]
        $GroupName,
        [Parameter(Mandatory = $true)]
        $authorization
    )

    #find Group descriptor
    $groupUri = "https://" + $vstsAccount + ".vssps.visualstudio.com/_apis/graph/groups?api-version=4.0-preview"
    $returnValue = Invoke-RestMethod -Uri $groupUri -Method Get -ContentType "application/json" -Headers $authorization
    Write-Host $returnValue

}

function GetVSTSProcesses() {
    Param(
        $userParams ,
        $authorization
    )
   
    try {
        $projectUri = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/DefaultCollection/_apis/process/processes?api-version=1.0"
        $returnValue = Invoke-RestMethod -Uri $projectUri -Method Get -ContentType "application/json" -Headers $authorization
        $id = ($returnValue.value).Where( {$_.name -eq $userParams.ProcessType})
        return $id.id
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-Host "Error : " + $ErrorMessage + " iTEM : " + $FailedItem
    }
  
}

function GetVSTSCredential () {
    Param(
        $userEmail,
        $Token
    )

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $userEmail, $token)))
    return @{Authorization = ("Basic {0}" -f $base64AuthInfo)}
}


# Adds a single user to a single team project within the specified TFS Group
function Add-TfsGroupMemberToTeamProjectGroup {
    param(
        [string]$TeamProject,
        [string]$TeamProjectGroupName,
        [string]$User,
        [pscustomobject]$TeamFoundationUserId)

    # Retrieve the list of groups within this TFS Team Project
    $readScopedGroupsUri = "$($globaltfs.root_url)/$TeamProject/_api/_identity/ReadScopedGroupsJson?__v=5"
    $params = @{ Uri = $readScopedGroupsUri; Method = 'Get' }
    $response = invoke_rest $params
	
    $grp = (($response | Select -ExpandProperty identities) | Where { $_.FriendlyDisplayName -eq $TeamProjectGroupName -and $_.IdentityType -eq "group" })

    # If we find the group then add the user here
    if ($grp -ne $null) {
        Write-Host "Found requested group $($grp.DisplayName) with ID $($grp.TeamFoundationId)"
        Write-Host "Verifying we can add to this group"

        # Verify we can add members to this group by calling the "CanAddMemberToGroup" api
        $uri = "$($globaltfs.root_url)/$TeamProject/_api/_identity/CanAddMemberToGroup?__v=5&groupId=$($grp.TeamFoundationId)"
        $params = @{ Uri = $uri; Method = 'Get' }
        $workerResponse = invoke_rest $params
		
        if ($workerResponse.canEdit -eq $true) {
            # Double check and ensure the user is not already a member of this group by reading it's members with the "ReadGroupMembers" API
            Write-Host "'Add' is supported for this group"
            Write-Host "Verifying '$User' is not already a member of this group"
			
            $uri = "$($globaltfs.root_url)/$TeamProject/_api/_identity/ReadGroupMembers?__v=5&scope=$($grp.TeamFoundationId)&readMembers=true"
            $params = @{ Uri = $uri; Method = 'Get' }
            $workerResponse = invoke_rest $params

            # Iterate through results and see if we find our user
            $existingUser = (($workerResponse | Select -ExpandProperty identities)  | Where { $_.TeamFoundationId -eq $TeamFoundationUserId.TeamFoundationId })

            # If the user doesn't exist then let's add them
            if ($existingUser -eq $null) {
                # Create a FORM body to be sent by POST to the "AddIdentities" API with the retrieved '__RequestVerificationToken' **We NEED this token!!**
                Write-Host "User '$user' does not exist. Adding to group..."
                $uri = "$($globaltfs.root_url)/$TeamProject/_api/_identity/AddIdentities?__v=5"
                $body = @{ newUsersJson = "[] "; `
                        existingUsersJson = "[`"$($TeamFoundationUserId.TeamFoundationId)`"]"; `
                        groupsToJoinJson = "[`"$($grp.TeamFoundationId)`"]"; `
                        __RequestVerificationToken = "$($globalSessionTokens.Tokens.RequestVerificationToken)" 
                }

                $params = @{ Uri = $uri; Method = 'Post'; ContentType = "application/x-www-form-urlencoded"; WebSession = $globalSessionTokens.TfsSession }
                $params.Add("Body", $body)

                $workerResponse = invoke_rest_with_response $params
				
                # Verify the response we get back from the API call to ensure it was successful. If not then write out the response with errors
                $json = ConvertFrom-Json -InputObject $workerResponse
                if ($json -ne $null) {
                    if ($json.HasErrors -eq $true) {
                        Write-Error ($json | Format-Table | Out-String)
                    }
                    else {
                        Write-Host "Successfully added user '$user' to group '$($grp.DisplayName)' in project '$TeamProject'"
                    }
                }
                else {
                    Write-Error "Failed to add user '$user' to group '$($grp.DisplayName)' in project '$TeamProject'. Please verify the server error reported."
                }
            }
            else {
                Write-Warning "User '$User' already exists within group '$TeamProjectGroupName' in project '$TeamProject'"
            }
        }
        else {
            Write-Error "Adding is NOT supported for group '$($grp.DisplayName)' in team project '$TeamProject'"
        }
    }
    else {
        Write-Warning "Could not find group '$TeamProjectGroupName' in Team Project '$TeamProject'"
    }
}


##############################
#
# this function will create the tfssecurity.exe command to change permissions for a given group and area
#
##############################
function GetSecurityCMD_old()
{
    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        $area,
        $actionType,
        $groupName,
        $permission
    )
     
    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail
   
    # get project id and then token
    $projectUri = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/DefaultCollection/_apis/projects?api-version=1.0"
    $allPrjects = Invoke-RestMethod -Uri $projectUri -Method Get -Headers $authorization  -ContentType "application/json"  
    $fnd = $allPrjects.value | Where-Object {$_.name -eq $userParams.ProjectName}

    $tkn +=  "$" + "PROJECT:vstfs:///Classification/TeamProject/" + $fnd.id  

    # $tmData =  @{ token =$tkn ;
    #     inheritPermissions = "false";
    #     acesDictionary = @( @{
    #         descriptor = "Microsoft.TeamFoundation.Identity;" +  [guid]::NewGuid();
    #         allow = 1;
    #         deny = 0;           
    #     })    
    #   }

    # $acl = ConvertTo-Json -InputObject $tmData
    # $acl = $acl -replace """{}""", '{}'
    
    # find group in security namespaces
    # $secURL = " https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/DefaultCollection/_apis/securitynamespaces/00000000-0000-0000-0000-000000000000/?api-version=1.0"
    # $namespaces = Invoke-RestMethod -Uri $secURL -Method Get -Headers $authorization -ContentType "application/json" 
    # $fnd = $namespaces.value | Where-Object {$_.name -eq $area}

    # get access control lists for given area = what to secure ie project, build, etc
    # $nmURL = " https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/_apis/accesscontrollists/" + $fnd.namespaceId + "?api-version=1.0"
    # $sec = Invoke-RestMethod -Uri $nmURL -Method Get -Headers $authorization -ContentType "application/json" 

    # $js =ConvertTo-Json -InputObject $sec.value
    # Out-File -FilePath "C:\temp\projectacl.json"  -InputObject $js 

    #find project id
    # $projectUri = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/DefaultCollection/_apis/projects?api-version=1.0"
    # $allPrjects = Invoke-RestMethod -Uri $projectUri -Method Get -Headers $authorization  -ContentType "application/json"  
    # $fnd = $allPrjects.value | Where-Object {$_.name -eq $userParams.ProjectName}

    $pth = "C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE\TFSSecurity.exe "
    $cmd = ""
    switch ($area) 
    {
        "Project" { $cmd += " /a+ Project " +  '"' + $tkn + '"'  } 
        "Build"   { $cmd += " /a+ Build " +  '"' + $tkn + '"' }
    } 

    # add action
    $cmd += " " +  $actionType 
   
    # add group to secure
    $cmd +=  " n:" + $([char]34) + "[" + $userParams.ProjectName + "]\" + $groupName + $([char]34) 
   
    # add permission  and collection
    $cmd += " $permission /collection:https://" + $userParams.VSTSMasterAcct + ".visualstudio.com"
    Write-Host $cmd

    Start-Process $pth -ArgumentList $cmd -NoNewWindow
    
}

function GetResources()
{

    Param(
        [Parameter(Mandatory = $true)]
        $FileName
      
    )

    Connect-AzureRmAccount     
    $rmResources = Get-AzureRmResource 

    Write-Output "Resource|Type|Resource Group|Subscription Id|Location" | Out-File $FileName  -NoNewline
    Write-Output "" | Out-File $FileName -Append

    foreach ($item in $rmResources) 
    {
        Write-Output $item.name "|" $item.ResourceType "|" $item.ResourceGroupName "|" $item.SubscriptionId "|" $item.Location | Out-File $FileName -Append -NoNewline
        Write-Output "" | Out-File $FileName -Append
    }


}

function Set-BuildDefinition()
{
    Param(
        [Parameter(Mandatory = $true)]
        $userParams,
        $repo
    )

    # Base64-encodes the Personal Access Token (PAT) appropriately
    $authorization = GetVSTSCredential -Token $userParams.PAT -userEmail $userParams.userEmail
   
    # find queue
    $queueCreateUrl = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/DefaultCollection/" + $userParams.ProjectName + "/_apis/distributedtask/queues?api-version=3.0-preview.1"
    $createBuild = Invoke-RestMethod -Uri $queueCreateUrl -Method Get -Headers $authorization  -ContentType "application/json"  
    $prjid = ""

    # if not found create it
    IF ($createBuild.count -eq 0) {
        
        $qDef = @{
            name = "My Queue";
            pool = @{ id = 1};
        }
        $qdefJson = ConvertTo-Json -InputObject $qDef
        $createqueue = Invoke-RestMethod -Uri $queueCreateUrl -Method Post -Headers $authorization  -ContentType "application/json"  -Body $qdefJson
        $prjid = $createqueue.id
    }
    else {
        $queueId  = ($createBuild.value | Where-Object {$_.name -eq $userParams.AgentQueue}).id
    }
    

    # $buildDef = @{
    #     name = $userParams.BuildName;
    #     type = "build";
    #     id = 0;
    #     quality = "definition";
    #     queue =  @{ id =  $prjid };
    #     build =  @(@{ 
    #         enabled = "true";   
    #         continueOnError = "false";
    #         displayName = "Build solution **\\*.sln";
    #         task = @{ id = (New-Guid).Guid ; versionSpec = "*" };
            
    #         inputs =  @{
    #             solution = "**\\*.sln";
    #             msbuildArgs = "";
    #             platform = "$" + "(platform)";
    #             configuration = "$" + "(config)";
    #             clean = "false";
    #             restoreNugetPackages = "true";
    #             vsLocationMethod = "version";
    #             vsVersion = "latest";
    #             vsLocation = "";
    #             msbuildLocationMethod = "version";
    #             msbuildVersion = "latest";
    #             msbuildArchitecture = "x86";
    #             msbuildLocation = "";
    #             logProjectEvents = "true"}; 
    #         };
    #         @{ 
    #         enabled = "true";
    #         continueOnError = "false";
    #         displayName = "Test Assemblies **\*test*.dll;-:**\obj\**";
    #         task = @{ id = New-Guid  ; versionSpec = "*" };

    #         inputs =  @{
    #             testAssembly = "**\*test*.dll;-:**\obj\**";
    #             testFiltercriteria = "";
    #             runSettingsFile = "";
    #             codeCoverageEnabled = "true";
    #             otherConsoleOptions = "";
    #             vsTestVersion = "14.0";
    #             pathtoCustomTestAdapters = ""};
    #         }                       
    #     )
    #     repository = @{
    #         id = $repo.id;
    #         type = "tfsgit";
    #         name =  $userParams.RepositoryName;
    #         localPath = "$" + "(sys.sourceFolder)/MyGitProject";
    #         defaultBranch = "/master";
    #         url = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/" + $userParams.ProjectName + "/_git/" + $userParams.RepositoryName;
    #         clean = "false";
    #     }
    #     options = @(@{
    #         enabled = "true";
    #         definition = @{ id = "1"};
    #         };
    #         @{
    #             inputs = @{ parallel = "false"; multipliers = "[\config\platform\]";}
    #         }
    #         );
    #     variables = @{
    #         forceClean = @{ value = "false"; allowOverride = "true";};
    #         config = @{ value = "debug, release"; allowOverride = "true";};
    #         platform = @{value = "any cpu"; allowOverride = "true";};
    #     }
    #     triggers = @();
    #     comments = "My first build definition";
    # }

    $buildTasks =  @(@{ 
        enabled = "true";
        continueOnError = "false";
        displayName = "Build solution **\\*.sln";
        task = @{ id = (New-Guid).Guid ; versionSpec = "*" };
        
        inputs =  @{
            solution = "**\\*.sln";
            msbuildArgs = "";
            platform = "$" + "(platform)";
            configuration = "$" + "(config)";
            clean = "false";
            restoreNugetPackages = "true";
            vsLocationMethod = "version";
            vsVersion = "latest";
            vsLocation = "";
            msbuildLocationMethod = "version";
            msbuildVersion = "latest";
            msbuildArchitecture = "x86";
            msbuildLocation = "";
            logProjectEvents = "true"}; 
        };
        @{ 
        enabled = "true";
        continueOnError = "false";
        displayName = "Test Assemblies **\*test*.dll;-:**\obj\**";
        task = @{ id = New-Guid  ; versionSpec = "*" };

        inputs =  @{
            testAssembly = "**\*test*.dll;-:**\obj\**";
            testFiltercriteria = "";
            runSettingsFile = "";
            codeCoverageEnabled = "true";
            otherConsoleOptions = "";
            vsTestVersion = "14.0";
            pathtoCustomTestAdapters = ""};
        }                       
    )

    $buildDefinition = @{
        "name"       = $userParams.RepositoryName
        "type"       = "build"
        "quality"    = "definition"
        "queue"      = @{
            "id" =  $queueId
        }
        "process"      = $BuildTasks
        "repository" = @{
            "id"            = $repo.id
            "type"          = "tfsgit"
            "name"          =  $userParams.RepositoryName
            "defaultBranch" = "refs/heads/master"
            "url"           = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/" + $userParams.ProjectName + "/_git/" + $userParams.RepositoryName
            "clean"         = $false
        }
        "options"    = @(
            @{
                "enabled"    = $true
                "definition" = @{
                    "id" = (New-Guid).Guid
                }
                "inputs"     = @{
                    "parallel"  = $false
                    multipliers = '["config","platform"]'
                }
            }
        )
        "variables"  = @{
            "system.debug" = @{
                "value"         = $false
                "allowOverride" = $true
            }
            "BuildConfiguration"     = @{
                "value"         = "release"
                "allowOverride" = $true
            }
            "BuildPlatform"   = @{
                "value"         = "any cpu"
                "allowOverride" = $true
            }
        }
        "triggers"   = @()
    }

    $buildjson = ConvertTo-Json -InputObject $buildDefinition -Depth 42
    Write-Host $buildjson

    # create build definition
    $buildUri = "https://" + $userParams.VSTSMasterAcct + ".visualstudio.com/DefaultCollection/" + $userParams.ProjectName + "/_apis/build/definitions?api-version=4.1-preview"
    $buildDef = Invoke-RestMethod -Uri $buildUri -Method Post -Headers $authorization  -ContentType "application/json"  -Body $buildjson
   
    Write-Host $buildDef


   
}

function Get-ResourceGroupBySubscription()
{
    #
    # this function will return the resource groups by azure subscriptions
    #
    Param(
        [Parameter(Mandatory = $true)]
        $userParams        
    )

    # connect to selected subscription
    Connect-AzureRmAccount -Subscription $userParams.Subscription

    $rg = Get-AzureRmResourceGroup
    $rgJson = ConvertTo-Json $rg
    Write-Host $rgJson
    
    $rd = Get-AzureRmRoleDefinition
    $rdJson = ConvertTo-Json $rd
    Write-Host $rdJson
    
    return $rg

}