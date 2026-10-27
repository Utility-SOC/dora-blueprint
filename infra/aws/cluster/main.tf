# The ephemeral half of the cloud lab: VPC + EKS + the IAM the platform's controllers need.
# `make cloud-up` / `make cloud-down`, or .github/workflows/cloud-lab.yaml. Everything that must
# outlive a teardown (state, evidence, backups) is in ../persistent instead.

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  vpc_cidr = "10.42.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  # terraform-aws-modules/vpc v6.7.3, pinned by commit (build-spec P3).
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=b3abd6df2ecf052451a361ed55b8f06f8742a795"

  name = var.name
  cidr = local.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(local.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(local.vpc_cidr, 8, i + 48)]
  intra_subnets   = [for i, _ in local.azs : cidrsubnet(local.vpc_cidr, 8, i + 52)]

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }

  # Network-level record of accepted and rejected flows -- the cloud-side complement to Hubble,
  # and evidence for the segmentation controls (DORA Art. 9, ISO A.8.20, NIST SC-7) that
  # doesn't depend on the CNI telling the truth about itself.
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = 7
  flow_log_max_aggregation_interval               = 60
}

module "eks" {
  # terraform-aws-modules/eks v21.29.0, pinned by commit.
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=91f11ea01656c26b8e6b8eb1b74f19863f60056c"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.admin_cidrs

  # API audit logging is what the Talos tier configures by hand (build-spec §2: "the single
  # highest-value log source for all three frameworks"). On EKS it goes to CloudWatch, not a
  # node file -- see docs/08-instantiation.md for what that changes in the detection path.
  enabled_log_types                      = ["audit", "api", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 7

  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for i, arn in var.admin_principal_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    workers = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      capacity_type  = var.capacity_type
      min_size       = var.node_count
      max_size       = var.node_count
      desired_size   = var.node_count
      disk_size      = 100
    }
  }
}

# ---- Pod Identity roles for the platform's own controllers ------------------------------------

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Velero: the persistent backup bucket (not MinIO -- MinIO stays the Talos tier's answer) plus
# EBS snapshots, per velero-plugin-for-aws's documented minimum policy.
resource "aws_iam_role" "velero" {
  name               = "${var.name}-velero"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "velero" {
  statement {
    actions = [
      "ec2:DescribeVolumes", "ec2:DescribeSnapshots", "ec2:CreateTags",
      "ec2:CreateVolume", "ec2:CreateSnapshot", "ec2:DeleteSnapshot",
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:DeleteObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = ["arn:aws:s3:::${var.backups_bucket}/*"]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.backups_bucket}"]
  }
  statement {
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "velero" {
  role   = aws_iam_role.velero.id
  policy = data.aws_iam_policy_document.velero.json
}

# Service account name is the vmware-tanzu/velero chart's default for a release named `velero`
# (apps/core/velero.yaml).
resource "aws_eks_pod_identity_association" "velero" {
  cluster_name    = module.eks.cluster_name
  namespace       = "velero"
  service_account = "velero-server"
  role_arn        = aws_iam_role.velero.arn
}
