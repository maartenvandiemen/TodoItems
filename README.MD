![Github CI](https://github.com/mvdiemen/TodoItems/actions/workflows/main.yml/badge.svg)


Demo project of an ASP.NET Core 7 minimal API's. Inspired by the demo from Daniel Roth that has been given at [dotnetconf](https://www.dotnetconf.net). See the original presentation below:<br>
[![YoutubePreview](http://img.youtube.com/vi/gNyEpkJMmcM/0.jpg)](http://www.youtube.com/watch?v=gNyEpkJMmcM)






## Prerequisites Azure Devops
The following prerequisites are required before performing the labs:

1. Ensure you have a Microsoft account
   - If you don't have a Microsoft account signup [here](https://account.microsoft.com) for a new one.
1. Browse to: https://dev.azure.com and select '_start for free_' <br> ![Sign up for Azure Devops](./.images/Prerequisites_SignUp.png)
1. Fill in the data and pick a name for your project. Set project visibility to '_private_' <br> ![Create project with visibility private](./.images/Prerequisites_CreateProjectVisibilityPrivate.png)
1. Note down the name of your Azure Devops organization you just created. The name of the organization is the same name as the project that is just created. So: `dev.azure.com/<JustCreatedProjectName>`
1. Create a request for parallel jobs [through this form](https://aka.ms/azpipelines-parallelism-request). Fill in with the following data: <br> ![Data required for parallelism request](./.images/Prerequisites_ParallelismRequest.png)
   - Wait untill the request is approved
1. [Import the code](https://learn.microsoft.com/en-us/azure/devops/repos/git/import-git-repository) of this repo in Azure Devops.
1. [Create a variable group](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups) with the name: TodoItemsApi-Build.
1. Create in this variable group a variable named: SA_PASSWORD. The value of this field should be a [complex password according to SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/security/password-policy). Make this field a secret.
