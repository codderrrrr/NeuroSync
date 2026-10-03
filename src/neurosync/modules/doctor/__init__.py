"""Doctor web portal: authentication, the patient roster, and clinical review.

Deliberately separate from patient authentication: a doctor session never
authenticates a patient endpoint and vice versa.

This package deliberately re-exports nothing; see ``monitoring/__init__.py`` for
the reason. Import ``neurosync.modules.doctor.router`` directly when the router
is what you need.
"""
