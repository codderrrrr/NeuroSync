"""Monitoring: assessment catalog, test plans, sessions, and recordings.

This package deliberately re-exports nothing. Importing a router here would run
it on every import of any submodule - including the pure comparison and routing
layers - and those layers sit *below* the routers, so the routers would import
back into them. Import ``neurosync.modules.monitoring.router`` directly when the
routers are what you need.
"""
