# Qwik-e-Classifier

1. Any tasks should be created at issues in the github repo. If you are taking on a task, assign that task to yourself. Some tasks might have multiple people. I’ve setup different labels for the issues:
- `docs` is for all documentation stuff (proposal, diagrams, basically any work we do thats not software or hardware)
- `hard`, `medium` and `easy` indicates the relative difficulty of the task. This will help us come up with estimates on time to complete tasks and help divide workload evenly.
- `software` is for the software related tasks (smart contract, node.js app, etc)
- `hardware` is for tasks relating to the actual mechanical hardware as well as the low level VHDL code for the FPGA.
- `bug` is for bugs

2. There is a project set up in the “project” tab. It works scrum style, we track whats todo, in progress, ready for testing, and done. New issues will automatically be added to the “To Do” column. When you are working on something, move it to the “In Progress” column. Each issue should have a Pull Request attached. Once the Pull Request is merged, close the issue and the card will automatically be moved to the “Ready for Testing” column. Once that feature is tested, we manually move that card to “Done”

3. Github workflow will be one repo with different branches for different features/tasks. *Don’t commit directly to master unless its some small documentation or something*, all your work should be on your own branches. So if I am working on a new feature or task, i would create a branch off master named “coin-acceptor”, or “vhdl-setup”, etc. Do all your work on that branch and then create a Pull Request to merge that branch into master once you are finished. In the PR description, reference the issue number(s) that PR is for. PR’s cannot be merged until they are reviewed by another person. If there are merge conflicts, rebase your branch on master (`> git rebase master`). 

4. Use the project proposal google doc to add any resources, useful links, libraries, etc under the “Available Source” section.

5. Commit any diagrams, flowcharts, documentation to github under the Docs folder.

6. Use the wiki for meeting notes, documentation, plans, etc (like in CMPUT 301)
