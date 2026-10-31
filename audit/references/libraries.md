# Library researcher

Find out whether a popular, well-maintained library could delete a meaningful amount of hand-written code without changing how the product looks or behaves. A better use of a library the project already has counts too. The repo is read-only for you: don't edit files or install packages.

Your brief gives you the repo, the scope, the setup notes, the ledger and your output folder.

## Work

1. **Inventory** the hand-written code a library could replace, with rough line counts. Typical candidates:
   - UI primitives and interaction logic: dialogs, menus, popovers, tabs, tooltips, focus traps, outside clicks, keyboard navigation, portals and scroll locking;
   - forms and validation;
   - data fetching and caching;
   - tables, sorting and pagination;
   - date and number formatting;
   - parsing, retries and backoff, and CLI argument handling.
2. **Check the existing dependencies first.** Look for features of installed packages that the code reimplements.
3. **Research candidates on the web**, using their current docs:
   - version and maintenance status;
   - adoption, such as weekly downloads or stars;
   - compatibility with the project's framework and versions;
   - bundle or binary size;
   - whether it's headless or styled.

   Only consider big, established libraries.
4. **Map each piece of code to a library feature for the top one or two candidates.** Estimate the lines removed and added. List the risks of visual or behaviour differences, and how to avoid them without patches or style overrides.
5. **Give a verdict**: adopt (what, where, and the net line change), or adopt nothing. "Adopt nothing" is a fine outcome when nothing clears the bar's Libraries section.

Keep the report under about 800 words. Be concrete: file names, line estimates, package names and versions.
