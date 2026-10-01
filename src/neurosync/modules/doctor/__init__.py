"""Doctor web portal: authentication and the patient roster.

Deliberately separate from patient authentication: a doctor session never
authenticates a patient endpoint and vice versa. Monitoring plans, assessment
assignment and clinical review are later slices and are not implemented here.
"""

from neurosync.modules.doctor.router import router

__all__ = ["router"]
