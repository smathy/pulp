pulp
====

This is a simple helper for [passenger](http://modrails.com/) in development.  It does two things:

 1. Simplifies the setup of new passenger virtual hosts by adding the necessary
    records to your apache config as well as to your hosts file.
 2. Checks your apache config to make sure that you have the right settings, and
    right order of settings (like that your passenger vhosts are **after** your
    `NameVirtualHost` directive).

It works magically, by querying apache itself to find the location of your conf
files.  It **isn't** magical enough to work on Windows.

Installation
------------

To perform a system wide installation:

	gem source -a http://gems.github.com
	gem install JasonKing-pulp

Usage
-----

Typically you'll setup a new rails app with the `rails` executable, and then
call `pulp` afterwards, like this:

    > rails foobar
    > sudo pulp foobar

Done.  You will now be able to visit http://foobar.dev/ and see your new rails
site running.

Contributors
------------
 
* Jason King (JasonKing)
