---
name: getting-started
description: A skill to help builders getting started building something on the build platform
---
# Getting Started Skill

A skill to help builders understand the general workflow of the build platform, and optionally provide a guided quickstart for new users.

## Instructions

1. First, explain the general "flow" of building on the platform. It ALWAYS follows this lifecycle:
   - **proto**: Edit the proto definition files in the `define` repository.
   - **define**: Run a define to generate the and packages from the proto
   definitions.
   - **packages**: Upgrade the generated packages in the `build` repository.
   - **code**: Write/edit the business logic (usually `.go` files).
   - **build**: Run a build on the `build` repository commit. Don't forget that
     the build image paths are relative to the neuron's folder. E.g. if the
   neuron is "demo-v1" with one top level Dockerfile, the image path is "." NOT
   "demo/v1"
   - **deploy**: Run a deploy to deploy the terraform in the neuron's infra folder (which probably uses the previously built docker image) to an environment (e.g., DEV).
   Also state that if the receiver of this info is a coding agent, they should
   guide the user through these steps.

2. Next, ask the user if they are completely new and would like to run the "simpleapi quickstart".

3. If the user says no, let them know you are ready to help them with any part of the `proto -> define -> packages -> code -> build -> deploy` flow whenever they need.

4. If the user says yes (they want the quickstart), follow these steps:
   - Ask the user to pick a product.
   - Ask the user for a new neuron id.
   - Create a neuron in that product.
   - Install the block with id='simpleapi' in the neuron.
   - Ask the user to open the definition's repo of the landing zone (`~/alis.build/{landing_zone_id}/define`), pull latest changes and merge in the newly created block branch into their master. They MUST remember to commit and push the merge. Ask them to just look at the proto file that was dropped for them, but not to make any changes yet. Ask them to revert back to you when they are done with the pushed commit sha, since you will need this sha to run define.
   - Once they let you know that they merged the branch, run a define on the 'HEAD' commit. Use the WaitForLastDefine tool to wait for the go packages to finish generating.
   - Ask them to open the product's build repo (`~/alis.build/{landing_zone_id}/build/{product_id}`), pull latest changes and merge in the newly created block branch into their master. They MUST remember to commit and push the merge. Ask them to just look at the files that were dropped for them, but not to make any changes yet. Ask them to install packages (which requires them to have preconfigured their environment, which is automatically done in vscode, otherwise they must ask you for help). They must try to run the go server locally and if it succeeds they must commit and push the expected changes in the go.mod and go.sum files. Once they are done they must let you know so you can build and deploy. Ideally they should provide you with the commit sha, but if they don't you may assume HEAD.
   - Once they let you know, run a build on the 'HEAD' commit. Provide the user with the logs url so they can see what is going on. Ask them to let you know once the build completes.
   - Upon build completion, run a deploy on the latest build of the neuron (assuming its successfully built) to deploy to the DEV environment. Provide the user with the logs url so they can see what is going on. Tell them that once the deploy completes they can go to cloudrun in their product's dev environment project (provide them with the project id or even better the url to the google cloud console at cloudrun with the project id as a query param). They should see their new service there.
   - Finally, remind them that they can now make edits to their protos or build code following the standard flow explained earlier!
