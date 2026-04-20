{{- define "model-service-stage3.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "model-service-stage3.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "model-service-stage3.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride -}}
{{- end -}}

{{- define "model-service-stage3.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "model-service-stage3.labels" -}}
helm.sh/chart: {{ include "model-service-stage3.chart" . }}
app.kubernetes.io/name: {{ include "model-service-stage3.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "model-service-stage3.selectorLabels" -}}
app.kubernetes.io/name: {{ include "model-service-stage3.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "model-service-stage3.cachePvcName" -}}
{{- printf "%s-cache" (include "model-service-stage3.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "model-service-stage3.serviceAccountName" -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
default
{{- end -}}
{{- end -}}

{{- define "model-service-stage3.imagePullSecretName" -}}
{{- default "ghcr-pull-secret" .Values.imagePullSecret.name -}}
{{- end -}}

{{- define "model-service-stage3.appSecretName" -}}
{{- if .Values.appSecret.name -}}
{{- .Values.appSecret.name -}}
{{- else -}}
{{- printf "%s-env" (include "model-service-stage3.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
