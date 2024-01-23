# Subscription Cross-Tenant Move in Azure
This project aims to improve the cross-tenant move of subscriptions in Azure. The project is part of the Microsoft Hackathon and is open-source.

## Introduction
Organizations might have several Azure subscriptions, each associated with a particular Azure Active Directory (Azure AD) directory. To make management easier, you might want to transfer a subscription to a different Azure AD directory. When you transfer a subscription to a different Azure AD directory, some resources are not transferred to the target directory. For example, all role assignments and custom roles in Azure role-based access control (Azure RBAC) are permanently deleted from the source directory and are not transferred to the target directory.

This project aims to address these issues and provide a seamless experience for cross-tenant subscription moves.