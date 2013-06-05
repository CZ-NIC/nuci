<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
		xmlns:uci-raw="http://www.nic.cz/ns/router/uci-raw"
		version="1.0">
  <xsl:output method="text"/>
  <xsl:strip-space elements="*"/>

  <!-- This parameter selects the part of the configuration that
       belongs to one output file in /etc/config. -->
  <xsl:param name="config">system</xsl:param>

  <xsl:param name="indent-step" select="4"/>
  <xsl:variable
      name="indent"
      select="substring('                ', 1, $indent-step)"/>
  <xsl:variable name="quote">'</xsl:variable>

  <xsl:template name="uci-string">
    <xsl:param name="text"/>
    <xsl:choose>
      <xsl:when test="contains($text, ' ') or contains($text, '&#x9;')">
	<xsl:choose>
	  <xsl:when test="contains($text, $quote)">
	    <xsl:text>"</xsl:text>
	    <xsl:value-of select="$text"/>
	    <xsl:text>"</xsl:text>
	  </xsl:when>
	</xsl:choose>
      </xsl:when>
      <xsl:otherwise>
	<xsl:value-of select="$text"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template name="name-value">
    <xsl:param name="name" select="uci-raw:name"/>
    <xsl:param name="value" select="uci-raw:value"/>
    <xsl:text> </xsl:text>
    <xsl:call-template name="uci-string">
      <xsl:with-param name="text" select="$name"/>
    </xsl:call-template>
    <xsl:text> </xsl:text>
    <xsl:call-template name="uci-string">
      <xsl:with-param name="text" select="$value"/>
    </xsl:call-template>
    <xsl:text>&#xA;</xsl:text>
  </xsl:template>

  <xsl:template match="/">
    <xsl:apply-templates
	select="descendant::uci-raw:uci/uci-raw:config[uci-raw:name=$config]"/>
  </xsl:template>

  <xsl:template match="uci-raw:config">
    <xsl:apply-templates select="uci-raw:section"/>
  </xsl:template>

  <xsl:template match="uci-raw:section[uci-raw:anonymous]">
    <xsl:text>config </xsl:text>
    <xsl:call-template name="uci-string">
      <xsl:with-param name="text" select="uci-raw:name"/>
    </xsl:call-template>
    <xsl:text>&#xA;</xsl:text>
    <xsl:apply-templates select="uci-raw:option|uci-raw:list"/>
  </xsl:template>

  <xsl:template match="uci-raw:section">
    <xsl:text>config</xsl:text>
    <xsl:call-template name="name-value">
      <xsl:with-param name="value" select="uci-raw:type"/>
    </xsl:call-template>
    <xsl:apply-templates select="uci-raw:option|uci-raw:list"/>
  </xsl:template>

  <xsl:template match="uci-raw:option">
    <xsl:value-of select="concat($indent, 'option')"/>
    <xsl:call-template name="name-value"/>
  </xsl:template>

  <xsl:template match="uci-raw:list">
    <xsl:for-each select="uci-raw:value">
      <xsl:value-of select="concat($indent, 'list')"/>
      <xsl:call-template name="name-value">
	<xsl:with-param name="name" select="../uci-raw:name"/>
	<xsl:with-param name="value" select="."/>
      </xsl:call-template>
    </xsl:for-each>
  </xsl:template>

</xsl:stylesheet>
